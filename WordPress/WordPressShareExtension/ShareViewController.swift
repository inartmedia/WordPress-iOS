import UIKit
import Social
import CoreData
import WordPressKit

class ShareViewController: SLComposeServiceViewController {

    // MARK: - Private Properties

    /// WordPress.com Username
    ///
    fileprivate lazy var wpcomUsername: String? = {
        ShareExtensionService.retrieveShareExtensionUsername()
    }()

    /// WordPress.com OAuth Token
    ///
    fileprivate lazy var oauth2Token: String? = {
        ShareExtensionService.retrieveShareExtensionToken()
    }()

    /// Selected Site's ID
    ///
    fileprivate lazy var selectedSiteID: Int? = {
        ShareExtensionService.retrieveShareExtensionDefaultSite()?.siteID
    }()

    /// Selected Site's Name
    ///
    fileprivate lazy var selectedSiteName: String? = {
        ShareExtensionService.retrieveShareExtensionDefaultSite()?.siteName
    }()

    /// Maximum Image Size
    ///
    fileprivate lazy var maximumImageSize: CGSize = {
        let dimension = ShareExtensionService.retrieveShareExtensionMaximumMediaDimension() ?? self.defaultMaxDimension
        return CGSize(width: dimension, height: dimension)
    }()

    /// Tracks Instance
    ///
    fileprivate lazy var tracks: Tracks = {
        Tracks(appGroupName: WPAppGroupName)
    }()

    /// MediaView Instance
    ///
    fileprivate var mediaView: MediaView!

    /// Image Attachments
    ///
    fileprivate var mediaImages: [UIImage]?

    /// Post's Status
    ///
    fileprivate var postStatus = "publish"

    /// Unique identifier for background sessions
    ///
    fileprivate lazy var backgroundSessionIdentifier: String = {
        let identifier = WPAppGroupName + "." + UUID().uuidString
        return identifier
    }()

    /// Unique identifier a group of upload operations
    ///
    fileprivate lazy var groupIdentifier: String = {
        let groupIdentifier = UUID().uuidString
        return groupIdentifier
    }()

    /// Core Data stack for application extensions
    ///
    fileprivate lazy var coreDataStack = SharedCoreDataStack()
    fileprivate var managedContext: NSManagedObjectContext!

    // MARK: - Private Constants

    fileprivate let defaultMaxDimension = 3000
    fileprivate let postStatuses = [
        // TODO: This should eventually be moved into WordPressComKit
        "draft": NSLocalizedString("Draft", comment: "Draft post status"),
        "publish": NSLocalizedString("Publish", comment: "Publish post status")
    ]

    fileprivate enum MediaSettings {
        static let filename = "image.jpg"
        static let mimeType = "image/jpeg"
    }

    // MARK: - UIViewController Methods

    override func viewDidLoad() {
        super.viewDidLoad()

        // Tracker
        tracks.wpcomUsername = wpcomUsername
        title = NSLocalizedString("WordPress", comment: "Application title")

        // Core Data
        managedContext = coreDataStack.managedContext
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        tracks.trackExtensionLaunched(oauth2Token != nil)
        dismissIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        coreDataStack.saveContext()
    }

    override func beginRequest(with context: NSExtensionContext) {
        super.beginRequest(with: context)
        loadContent(extensionContext: context)
    }


    // MARK: - SLComposeService Overriden Methods

    override func loadPreviewView() -> UIView! {
        return mediaView
    }

    override func isContentValid() -> Bool {
        // Even when the oAuth Token is nil, it's possible the default site hasn't been retrieved yet.
        // Let's disable Post, until the user picks a valid site.
        //
        var validContent = false
        if let extensionContext = extensionContext {
            validContent = ShareExtractor(extensionContext: extensionContext).validContent
        }
        let containsText = contentText.isEmpty == false

        return selectedSiteID != nil && (containsText || validContent)
    }

    override func didSelectCancel() {
        tracks.trackExtensionCancelled()
        super.didSelectCancel()
    }

    override func didSelectPost() {
        guard let _ = oauth2Token, let siteID = selectedSiteID else {
            fatalError("The view should have been dismissed on viewDidAppear!")
        }

        // Save the last used site
        if let siteName = selectedSiteName {
            ShareExtensionService.configureShareExtensionLastUsedSiteID(siteID, lastUsedSiteName: siteName)
        }

        // Proceed uploading the actual post
        let (subject, body) = contentText.stringWithAnchoredLinks().splitContentTextIntoSubjectAndBody()
        if let images = mediaImages {
            var allEncodedMedia = [Data?]()
            images.flatMap({ $0 }).forEach({ image in
                let encodedMedia = image.resizeWithMaximumSize(maximumImageSize).JPEGEncoded()
                allEncodedMedia.append(encodedMedia)
            })

            uploadPostWithMedia(subject: subject,
                                body: body,
                                status: postStatus,
                                siteID: siteID,
                                attachedImageData: allEncodedMedia,
                                requestEnqueued: {
                                    self.tracks.trackExtensionPosted(self.postStatus)
                                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            })
        } else {
            let remotePost: RemotePost = {
                let post = RemotePost()
                post.siteID = NSNumber(value: siteID)
                post.status = postStatus
                post.title = subject
                post.content = body
                return post
            }()
            let uploadPostOpID = savePostOperation(remotePost, with: .inProgress)
            uploadPost(forUploadOpWithObjectID: uploadPostOpID, requestEnqueued: {
                self.tracks.trackExtensionPosted(self.postStatus)
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            })
        }
    }

    override func configurationItems() -> [Any]! {
        let blogPickerItem = SLComposeSheetConfigurationItem()!
        blogPickerItem.title = NSLocalizedString("Post to:", comment: "Upload post to the selected Site")
        blogPickerItem.value = selectedSiteName ?? NSLocalizedString("Select a site", comment: "Select a site in the share extension")
        blogPickerItem.tapHandler = { [weak self] in
            self?.displaySitePicker()
        }

        let statusPickerItem = SLComposeSheetConfigurationItem()!
        statusPickerItem.title = NSLocalizedString("Post Status:", comment: "Post status picker title in Share Extension")
        statusPickerItem.value = postStatuses[postStatus]!
        statusPickerItem.tapHandler = { [weak self] in
            self?.displayStatusPicker()
        }

        return [blogPickerItem, statusPickerItem]
    }
}

// MARK: - ShareViewController Extension: Encapsulates all of the Action Helpers.

private extension ShareViewController {
    func dismissIfNeeded() {
        guard oauth2Token == nil else {
            return
        }

        let title = NSLocalizedString("No WordPress.com Account", comment: "Extension Missing Token Alert Title")
        let message = NSLocalizedString("Launch the WordPress app and log into your WordPress.com or Jetpack site to share.", comment: "Extension Missing Token Alert Title")
        let accept = NSLocalizedString("Cancel Share", comment: "Dismiss Extension and cancel Share OP")

        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let alertAction = UIAlertAction(title: accept, style: .default) { (action) in
            self.cancel()
        }

        alertController.addAction(alertAction)
        present(alertController, animated: true, completion: nil)
    }

    func displaySitePicker() {
        let pickerViewController = SitePickerViewController()
        pickerViewController.onChange = { (siteId, description) in
            self.selectedSiteID = siteId
            self.selectedSiteName = description
            self.reloadConfigurationItems()
            self.validateContent()
        }

        pushConfigurationViewController(pickerViewController)
    }

    func displayStatusPicker() {
        let pickerViewController = PostStatusPickerViewController(statuses: postStatuses)
        pickerViewController.onChange = { (status, description) in
            self.postStatus = status
            self.reloadConfigurationItems()
        }

        pushConfigurationViewController(pickerViewController)
    }
}

// MARK: - ShareViewController Extension: Encapsulates private helpers

private extension ShareViewController {
    func loadContent(extensionContext: NSExtensionContext) {
        ShareExtractor(extensionContext: extensionContext)
            .loadShare(completion: { [weak self] share in
                self?.textLoaded(text: share.text)
                if share.images.count > 0 {
                    self?.imagesLoaded(images: share.images)
                }
        })
    }

    func textLoaded(text: String) {
        guard text.count > 0 else {
            return
        }
        var content = ""
        if let contentText = contentText {
            content.append("\(contentText)\n\n")
        }
        content.append(text)
        textView.text = content
    }

    func imagesLoaded(images: [UIImage]) {
        let mediaView = MediaView()
        if let image = images.first {
            // Load the View with the first image only
            mediaView.resizeIfNeededAndDisplay(image)
        }

        // References please
        self.mediaImages = images
        self.mediaView = mediaView
        self.reloadConfigurationItems()
    }
}

// MARK: - ShareViewController Extension: Persistence

private extension ShareViewController {
    func saveMediaOperation(_ remoteMedia: RemoteMedia, with status: UploadOperation.UploadStatus, siteID: NSNumber) -> NSManagedObjectID {
        let mediaUploadOp = MediaUploadOperation(context: managedContext)
        mediaUploadOp.updateWithMedia(remote: remoteMedia)
        mediaUploadOp.backgroundSessionIdentifier = backgroundSessionIdentifier
        mediaUploadOp.groupID = groupIdentifier
        mediaUploadOp.created = NSDate()
        mediaUploadOp.currentStatus = status
        mediaUploadOp.siteID = siteID.int64Value
        coreDataStack.saveContext()
        return mediaUploadOp.objectID
    }

    func savePostOperation(_ remotePost: RemotePost, with status: UploadOperation.UploadStatus) -> NSManagedObjectID {
        let postUploadOp = PostUploadOperation(context: managedContext)
        postUploadOp.updateWithPost(remote: remotePost)
        postUploadOp.groupID = groupIdentifier
        postUploadOp.created = NSDate()
        postUploadOp.currentStatus = status
        coreDataStack.saveContext()
        return postUploadOp.objectID
    }

    func updatePostOperation(status: UploadOperation.UploadStatus, remotePostID: Int64, forPostUploadOpWithObjectID postUploadOpObjectID: NSManagedObjectID) {
        guard let postUploadOp = (try? managedContext.existingObject(with: postUploadOpObjectID)) as? PostUploadOperation else {
            DDLogError("Error loading PostUploadOperation Object with ID: \(postUploadOpObjectID)")
            return
        }
        postUploadOp.currentStatus = status
        postUploadOp.remotePostID = remotePostID
        coreDataStack.saveContext()
    }

    func updateStatus(_ status: UploadOperation.UploadStatus, forUploadOpWithObjectID uploadOpObjectID: NSManagedObjectID) {
        var uploadOp: UploadOperation?
        do {
            uploadOp = try managedContext.existingObject(with: uploadOpObjectID) as? UploadOperation
        } catch {
            DDLogError("Error loading UploadOperation Object with ID: \(uploadOpObjectID)")
            return
        }
        uploadOp?.currentStatus = status
        coreDataStack.saveContext()
    }

    func updateTaskID(_ taskID: NSNumber, forUploadOpWithObjectID uploadOpObjectID: NSManagedObjectID) {
        var uploadOp: UploadOperation?
        do {
            uploadOp = try managedContext.existingObject(with: uploadOpObjectID) as? UploadOperation
        } catch {
            DDLogError("Error loading UploadOperation Object with ID: \(uploadOpObjectID)")
            return
        }
        uploadOp?.backgroundSessionTaskID = taskID.int32Value
        coreDataStack.saveContext()
    }

    func fetchPostUploadOp(withObjectID postUploadOpObjectID: NSManagedObjectID) -> PostUploadOperation? {
        var postUploadOp: PostUploadOperation?
        do {
            postUploadOp = try managedContext.existingObject(with: postUploadOpObjectID) as? PostUploadOperation
        } catch {
            DDLogError("Error loading PostUploadOperation Object with ID: \(postUploadOpObjectID)")
        }
        return postUploadOp
    }

    func fetchMediaUploadOpsForGroup(_ groupID: String) -> [MediaUploadOperation]? {
        var mediaUploadOps: [MediaUploadOperation]
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "MediaUploadOperation")
        request.predicate = NSPredicate(format: "(groupID == %@)", groupID)
        do {
            mediaUploadOps = try managedContext.fetch(request) as! [MediaUploadOperation]
        } catch {
            fatalError("Failed to fetch MediaUploadOperation: \(error)")
        }

        return mediaUploadOps
    }
}

// MARK: - ShareViewController Extension: Backend Interaction

private extension ShareViewController {
    func combinePostWithMediaAndUpload(forPostUploadOpWithObjectID uploadPostOpID: NSManagedObjectID) {
        guard let postUploadOp = fetchPostUploadOp(withObjectID: uploadPostOpID),
            let groupID = postUploadOp.groupID,
            let mediaUploadOps = fetchMediaUploadOpsForGroup(groupID) else {
                return
        }

        let remoteURLText = mediaUploadOps.flatMap({ $0.remoteURL }).map({ "".stringByPrependingMediaURL($0) }).joined()
        let content = postUploadOp.postContent ?? ""
        postUploadOp.postContent = content + remoteURLText
        coreDataStack.saveContext()

        self.uploadPost(forUploadOpWithObjectID: uploadPostOpID, requestEnqueued: {})
    }

    func uploadPost(forUploadOpWithObjectID uploadOpObjectID: NSManagedObjectID, requestEnqueued: @escaping () -> ()) {
        guard let postUploadOp = fetchPostUploadOp(withObjectID: uploadOpObjectID) else {
                DDLogError("Error uploading post in share extension — could not fetch saved post.")
                requestEnqueued()
                return
        }

        let remotePost = postUploadOp.remotePost

        // 15-Nov-2017: Creating a post without media on the PostServiceRemoteREST does not use background uploads so set it false
        let api = WordPressComRestApi(oAuthToken: oauth2Token,
                                      userAgent: nil,
                                      backgroundUploads: false,
                                      backgroundSessionIdentifier: backgroundSessionIdentifier,
                                      sharedContainerIdentifier: WPAppGroupName)
        let remote = PostServiceRemoteREST(wordPressComRestApi: api, siteID: NSNumber(value: postUploadOp.siteID))
        remote.createPost(remotePost, success: { post in
            if let post = post {
                DDLogInfo("Post \(post.postID.stringValue) sucessfully uploaded to site \(post.siteID.stringValue)")
                if let postID = post.postID {
                    self.updatePostOperation(status: .complete, remotePostID: postID.int64Value, forPostUploadOpWithObjectID: uploadOpObjectID)
                } else {
                    self.updateStatus(.complete, forUploadOpWithObjectID: uploadOpObjectID)
                }
            }
            requestEnqueued()
        }, failure: { error in
            var errorString = "Error creating post in share extension"
            if let error = error as NSError? {
                errorString += ": \(error.localizedDescription)"
            }
            DDLogError(errorString)
            self.updateStatus(.error, forUploadOpWithObjectID: uploadOpObjectID)
            requestEnqueued()
        })
    }

    func uploadPostWithMedia(subject: String, body: String, status: String, siteID: Int, attachedImageData: [Data?]?, requestEnqueued: @escaping () -> ()) {
        guard let attachedImageData = attachedImageData,
            let mediaDirectory = ShareMediaFileManager.shared.mediaUploadDirectoryURL else {
                DDLogError("No media is attached to this upload request.")
                requestEnqueued()
                return
        }

        // First create the post upload op
        let remotePost: RemotePost = {
            let post = RemotePost()
            post.siteID = NSNumber(value: siteID)
            post.status = status
            post.title = subject
            post.content = body
            return post
        }()
        let uploadPostOpID = savePostOperation(remotePost, with: .pending)

        // Now process all of the media items and create their upload ops
        var uploadMediaOpIDs = [NSManagedObjectID]()
        var allRemoteMedia = [RemoteMedia]()
        attachedImageData.flatMap({ $0 }).forEach { imageData in
            let uniqueString = "image_\(NSDate.timeIntervalSinceReferenceDate)"
            let fileName = uniqueString.components(separatedBy: ["."]).joined() + ".jpg"
            let fullPath = mediaDirectory.appendingPathComponent(fileName)
            let remoteMedia: RemoteMedia = {
                let media = RemoteMedia()
                media.file = fileName
                media.mimeType = MediaSettings.mimeType
                media.localURL = fullPath
                return media
            }()
            allRemoteMedia.append(remoteMedia)

            do {
                try imageData.write(to: fullPath, options: [.atomic])
            } catch {
                DDLogError("Error saving \(fullPath) to shared container: \(String(describing: error))")
                return
            }
            let uploadMediaOpID = saveMediaOperation(remoteMedia, with: .pending, siteID: NSNumber(value: siteID))
            uploadMediaOpIDs.append(uploadMediaOpID)
        }

        // Upload the media items
        let api = WordPressComRestApi(oAuthToken: oauth2Token,
                                      userAgent: nil,
                                      backgroundUploads: true,
                                      backgroundSessionIdentifier: backgroundSessionIdentifier,
                                      sharedContainerIdentifier: WPAppGroupName)

        // NOTE: The success and error closures **may** get called here - it’s non-deterministic as to whether WPiOS
        // or the extension gets the "did complete" callback. So unfortunatly, we need to have the logic to complete
        // post share here as well as WPiOS.
        let remote = MediaServiceRemoteREST.init(wordPressComRestApi: api, siteID: NSNumber(value: siteID))
        remote.uploadMedia(allRemoteMedia, requestEnqueued: { taskID in
            uploadMediaOpIDs.forEach({ uploadMediaOpID in
                self.updateStatus(.inProgress, forUploadOpWithObjectID: uploadMediaOpID)
                if let taskID = taskID {
                    self.updateTaskID(taskID, forUploadOpWithObjectID: uploadMediaOpID)
                }
            })
            requestEnqueued()
        }, success: { remoteMedia in
            guard let returnedMedia = remoteMedia as? [RemoteMedia],
                returnedMedia.count > 0,
                let mediaUploadOps = self.fetchMediaUploadOpsForGroup(self.groupIdentifier) else {
                    DDLogError("Error creating post in share extension. RemoteMedia info not returned from server.")
                    return
            }

            mediaUploadOps.forEach({ mediaUploadOp in
                returnedMedia.forEach({ remoteMedia in
                    if let remoteMediaID = remoteMedia.mediaID?.int64Value,
                        let remoteMediaURLString = remoteMedia.url?.absoluteString,
                        let localFileName = mediaUploadOp.fileName,
                        let remoteFileName = remoteMedia.file {

                        if localFileName.lowercased().trim() == remoteFileName.lowercased().trim() {
                            mediaUploadOp.remoteURL = remoteMediaURLString
                            mediaUploadOp.remoteMediaID = remoteMediaID
                            mediaUploadOp.currentStatus = .complete
                            ShareMediaFileManager.shared.removeFromUploadDirectory(fileName: localFileName)
                        }
                    }
                })
            })
            self.coreDataStack.saveContext()

            // Now upload the post
            self.combinePostWithMediaAndUpload(forPostUploadOpWithObjectID: uploadPostOpID)
        }) { error in
            guard let error = error as NSError? else {
                return
            }
            DDLogError("Error creating post in share extension: \(error.localizedDescription)")
            uploadMediaOpIDs.forEach({ uploadMediaOpID in
                self.updateStatus(.error, forUploadOpWithObjectID: uploadMediaOpID)
            })
            self.tracks.trackExtensionError(error)
        }
    }
}
