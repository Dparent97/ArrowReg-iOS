import SwiftUI
import UIKit

/// A UIViewControllerRepresentable wrapper around UIPageViewController to
/// provide reliable paging gestures inside complex SwiftUI hierarchies.
struct PagingView<Content: View>: UIViewControllerRepresentable {
    var pages: [Content]
    @Binding var currentIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        
        // Initialize controllers
        context.coordinator.updateControllers(pages: pages)
        
        if let first = context.coordinator.controllers.first {
            controller.setViewControllers([first], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        // Update controllers if pages changed
        context.coordinator.updateControllers(pages: pages)
        
        let controllers = context.coordinator.controllers
        guard currentIndex < controllers.count else { return }
        
        // Only update if currentIndex actually changed
        if currentIndex != context.coordinator.currentIndex {
            let direction: UIPageViewController.NavigationDirection = currentIndex >= context.coordinator.currentIndex ? .forward : .reverse
            pageViewController.setViewControllers([controllers[currentIndex]], direction: direction, animated: true)
            context.coordinator.currentIndex = currentIndex
        }
    }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagingView
        var controllers: [UIViewController] = []
        var currentIndex: Int = 0

        init(_ parent: PagingView) { self.parent = parent }
        
        func updateControllers(pages: [Content]) {
            controllers = pages.map { UIHostingController(rootView: $0) }
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = controllers.firstIndex(of: viewController), index > 0 else { return nil }
            return controllers[index - 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = controllers.firstIndex(of: viewController), index + 1 < controllers.count else { return nil }
            return controllers[index + 1]
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let visible = pageViewController.viewControllers?.first, let index = controllers.firstIndex(of: visible) {
                currentIndex = index
                parent.currentIndex = index
            }
        }
    }
}
