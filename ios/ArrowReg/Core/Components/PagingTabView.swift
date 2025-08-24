import SwiftUI
import UIKit

/// A paging container backed by `UIPageViewController` to provide
/// reliable horizontal swipe navigation between SwiftUI views.
struct PagingTabView<Content: View>: UIViewControllerRepresentable {
    @Binding var currentPage: Int
    var pages: [Content]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator

        if let first = context.coordinator.controllers.first {
            controller.setViewControllers([first], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.updateControllers(pages: pages)

        let direction: UIPageViewController.NavigationDirection =
            currentPage >= context.coordinator.currentPage ? .forward : .reverse

        if let visible = context.coordinator.controllers[safe: currentPage] {
            uiViewController.setViewControllers([visible], direction: direction, animated: true)
        }

        context.coordinator.currentPage = currentPage
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagingTabView
        var controllers: [UIHostingController<Content>] = []
        var currentPage: Int = 0

        init(_ parent: PagingTabView) {
            self.parent = parent
            super.init()
            updateControllers(pages: parent.pages)
        }

        func updateControllers(pages: [Content]) {
            controllers = pages.map { UIHostingController(rootView: $0) }
        }

        // MARK: UIPageViewControllerDataSource
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = controllers.firstIndex(of: viewController as! UIHostingController<Content>), index > 0 else {
                return nil
            }
            return controllers[index - 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = controllers.firstIndex(of: viewController as! UIHostingController<Content>), index + 1 < controllers.count else {
                return nil
            }
            return controllers[index + 1]
        }

        // MARK: UIPageViewControllerDelegate
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let current = pageViewController.viewControllers?.first,
               let index = controllers.firstIndex(of: current as! UIHostingController<Content>) {
                currentPage = index
                parent.currentPage = index
            }
        }
    }
}

// MARK: - Safe Array Indexing
private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
