class QuickStartChecklistManager: NSObject {
    typealias QuickStartChecklistDidSelectTour = (String) -> Void
    typealias QuickStartChecklistDidTapHeader = (Bool) -> Void

    private var blog: Blog
    private var tours: [QuickStartTour]
    private var todoTours: [QuickStartTour] = []
    private var completedTours: [QuickStartTour] = []
    private var completedToursKeys = Set<String>()
    private var didSelectTour: QuickStartChecklistDidSelectTour
    private var didTapHeader: QuickStartChecklistDidTapHeader
    private var completedSectionCollapse: Bool = false

    init(blog: Blog,
         tours: [QuickStartTour],
         didSelectTour: @escaping QuickStartChecklistDidSelectTour,
         didTapHeader: @escaping QuickStartChecklistDidTapHeader) {
        self.blog = blog
        self.tours = tours
        self.didSelectTour = didSelectTour
        self.didTapHeader = didTapHeader
        super.init()
        reloadData()
    }

    func reloadData() {
        let completed = (blog.completedQuickStartTours ?? []).map { $0.tourID }
        completedToursKeys = Set(completed)
        todoTours = tours.filter(!isCompleted)
        completedTours = tours.filter(isCompleted)
    }

    func tour(at indexPath: IndexPath) -> QuickStartTour {
        return tours(at: indexPath.section)[indexPath.row]
    }

    func shouldShowCompleteTasksScreen() -> Bool {
        return todoTours.isEmpty
    }
}

extension QuickStartChecklistManager: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Sections.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tours(at: section).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: QuickStartChecklistCell.reuseIdentifier) as? QuickStartChecklistCell {
            let tour = self.tour(at: indexPath)
            cell.tour = tour
            cell.completed = isCompleted(tour: tour)
            cell.lastRow = isLastTour(at: indexPath)
            return cell
        }
        return UITableViewCell()
    }
}

extension QuickStartChecklistManager: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if tour(at: indexPath) is QuickStartCreateTour {
            return nil
        }
        return indexPath
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let tourGuide = QuickStartTourGuide.find() else {
                return
        }

        let tour = self.tour(at: indexPath)
        tourGuide.start(tour: tour, for: blog)
        didSelectTour(tour.analyticsKey)
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        if section == Sections.todo.rawValue,
            !todoTours.isEmpty,
            !completedTours.isEmpty {
            return UIView()
        }
        return nil
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if section == Sections.todo.rawValue,
            !todoTours.isEmpty,
            !completedTours.isEmpty {
            return Sections.footerHeight
        }
        return 0.0
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if section == Sections.completed.rawValue,
            !completedTours.isEmpty {
            let headerView = Bundle.main.loadNibNamed("QuickStartChecklistHeader", owner: nil, options: nil)?.first as? QuickStartChecklistHeader
            headerView?.collapse = completedSectionCollapse
            headerView?.count = completedTours.count
            headerView?.collapseListener = { [weak self] collapse in
                self?.completedSectionCollapse = collapse
                self?.tableView(tableView, reloadCompletedSection: collapse)
            }
            return headerView
        }
        return nil
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == Sections.completed.rawValue,
            !completedTours.isEmpty {
            return Sections.headerHeight
        }
        return 0.0
    }
}

private extension QuickStartChecklistManager {
    func isLastTour(at indexPath: IndexPath) -> Bool {
        let tours = self.tours(at: indexPath.section)
        return (tours.count - 1) == indexPath.row
    }

    func tours(at section: Int) -> [QuickStartTour] {
        guard let section = Sections(rawValue: section) else {
            return []
        }

        switch section {
        case .todo:
            return todoTours
        case .completed:
            return completedSectionCollapse ? completedTours : []
        }
    }

    func isCompleted(tour: QuickStartTour) -> Bool {
        return completedToursKeys.contains(tour.key)
    }

    func tableView(_ tableView: UITableView, reloadCompletedSection collapsing: Bool) {
        var indexPaths: [IndexPath] = []
        for (index, _) in completedTours.enumerated() {
            indexPaths.append(IndexPath(row: index, section: Sections.completed.rawValue))
        }

        if collapsing {
            tableView.insertRows(at: indexPaths, with: .fade)
        } else {
            tableView.deleteRows(at: indexPaths, with: .fade)
        }

        didTapHeader(collapsing)
    }
}

private enum Sections: Int, CaseIterable {
    static let footerHeight = CGFloat(20.0)
    static let headerHeight = CGFloat(44.0)

    case todo
    case completed
}
