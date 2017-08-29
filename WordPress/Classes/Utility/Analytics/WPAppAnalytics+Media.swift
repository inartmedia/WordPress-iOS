/// Utility extension to track specific data for passing to on to WPAppAnalytics.
public extension WPAppAnalytics {

    /// Used to identify where the seleeted media came from
    ///
    public enum SelectedMediaOrigin: CustomStringConvertible {
        case InlinePicker
        case FullScreenPicker
        case None

        public var description: String {
            switch self {
            case .InlinePicker: return "inline_picker"
            case .FullScreenPicker: return "full_screen_picker"
            case .None: return "not_identified"
            }
        }
    }

    /// Get a dictionary of tracking properties for a Media object with the selected media origin.
    ///
    /// - Parameters:
    ///     - media: The Media object.
    ///     - mediaOrigin: The Media's origin.
    /// - Returns: Dictionary
    ///
    public class func properties(for media: Media, mediaOrigin: SelectedMediaOrigin) -> Dictionary<String, Any> {
        var properties = WPAppAnalytics.properties(for: media)
        properties[MediaOrigin] = mediaOrigin.description
        return properties
    }

    /**
     Get a dictionary of tracking properties for a Media object.
     - parameter media: the Media object
     - returns: Dictionary
     */
    public class func properties(for media: Media) -> Dictionary<String, Any> {
        var properties = [String: Any]()
        properties[MediaProperties.mime] = media.mimeType()
        if let fileExtension = media.fileExtension(), !fileExtension.isEmpty {
            properties[MediaProperties.fileExtension] = fileExtension
        }
        if media.mediaType == .image {
            if let width = media.width, let height = media.height {
                let megaPixels = round((width.floatValue * height.floatValue) / 1000000)
                properties[MediaProperties.megapixels] = Int(megaPixels)
            }
        } else if media.mediaType == .video {
            properties[MediaProperties.durationSeconds] = media.length
        }
        if let filesize = media.filesize {
            properties[MediaProperties.bytes] = filesize.intValue * 1024
        }
        return properties
    }

    fileprivate struct MediaProperties {
        static let mime = "mime"
        static let fileExtension = "ext"
        static let megapixels = "megapixels"
        static let durationSeconds = "duration_secs"
        static let bytes = "bytes"
    }

    fileprivate static let MediaOrigin = "media_origin"
}
