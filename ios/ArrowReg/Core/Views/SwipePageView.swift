import SwiftUI
import UIKit

/// A UIKit-backed paging view that enables reliable horizontal swiping between pages.
/// This wrapper uses `UIPageViewController` under the hood which provides a more
/// predictable gesture handling compared to SwiftUI's `TabView` with `.page` style.
struct SwipePageView<Content: View>: UIViewControllerRepresentable {
    /// The pages to display.
    var pages: [Content]
    /// The currently selected page index.
    @Binding var currentIndex: Int

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
        // Set initial controller
        if let first = context.coordinator.controllers[safe: currentIndex] {
            controller.setViewControllers([first], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.updatePages(pages)
        guard let target = context.coordinator.controllers[safe: currentIndex] else { return }
        let direction: UIPageViewController.NavigationDirection = currentIndex >= context.coordinator.currentPage ? .forward : .reverse
        controller.setViewControllers([target], direction: direction, animated: true)
        context.coordinator.currentPage = currentIndex
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: SwipePageView
        var controllers: [UIViewController]
        var currentPage: Int

        init(_ parent: SwipePageView) {
            self.parent = parent
            self.controllers = parent.pages.map { UIHostingController(rootView: $0) }
            self.currentPage = parent.currentIndex
        }

        func updatePages(_ pages: [Content]) {
            controllers = pages.map { UIHostingController(rootView: $0) }
        }

        // MARK: UIPageViewControllerDataSource
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = controllers.firstIndex(of: viewController), index > 0 else { return nil }
            return controllers[index - 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = controllers.firstIndex(of: viewController), index + 1 < controllers.count else { return nil }
            return controllers[index + 1]
        }

        // MARK: UIPageViewControllerDelegate
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let visible = pageViewController.viewControllers?.first, let index = controllers.firstIndex(of: visible) {
                currentPage = index
                parent.currentIndex = index
            }
        }
    }
}

// MARK: - Array safe index helper
private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

