import SwiftUI
import UIKit

/// A UIViewControllerRepresentable wrapper around UIPageViewController to provide
/// reliable horizontal paging within SwiftUI contexts like nested ScrollViews.
struct PageView<Page: View>: UIViewControllerRepresentable {
    var pages: [Page]
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal)
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator

        if let first = context.coordinator.controllers.first {
            controller.setViewControllers([first], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let direction: UIPageViewController.NavigationDirection =
            context.coordinator.currentIndex <= currentPage ? .forward : .reverse
        context.coordinator.currentIndex = currentPage
        controller.setViewControllers([context.coordinator.controllers[currentPage]], direction: direction, animated: true)
    }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageView
        var controllers: [UIViewController]
        var currentIndex: Int

        init(_ parent: PageView) {
            self.parent = parent
            self.controllers = parent.pages.map { UIHostingController(rootView: $0) }
            self.currentIndex = parent.currentPage
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = controllers.firstIndex(of: viewController), index > 0 else { return nil }
            return controllers[index - 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = controllers.firstIndex(of: viewController), index + 1 < controllers.count else { return nil }
            return controllers[index + 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            if completed, let visible = pageViewController.viewControllers?.first,
               let index = controllers.firstIndex(of: visible) {
                currentIndex = index
                parent.currentPage = index
            }
        }
    }
}
