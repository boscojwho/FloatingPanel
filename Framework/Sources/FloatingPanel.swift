//
//  Copyright © 2018 Shin Yamamoto. All rights reserved.
//

import UIKit

///
/// FloatingPanel presentation model
///
class FloatingPanel: NSObject, UIGestureRecognizerDelegate, UIScrollViewDelegate {
    /* Cause 'terminating with uncaught exception of type NSException' error on Swift Playground
     unowned let view: UIView
     */
    let surfaceView: FloatingPanelSurfaceView
    let backdropView: FloatingPanelBackdropView
    var layoutAdapter: FloatingPanelLayoutAdapter
    var behavior: FloatingPanelBehavior

    weak var scrollView: UIScrollView? {
        didSet {
            guard let scrollView = scrollView else { return }
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handle(panGesture:)))
            scrollViewState.scrollIndicatorsVisible = scrollView.showsVerticalScrollIndicator
        }
    }
    weak var userScrollViewDelegate: UIScrollViewDelegate?

    var safeAreaInsets: UIEdgeInsets! {
        get { return layoutAdapter.safeAreaInsets }
        set { layoutAdapter.safeAreaInsets = newValue }
    }

    unowned let viewcontroller: FloatingPanelController

    let panGesture: FloatingPanelPanGestureRecognizer
    
    private var animator: UIViewPropertyAnimator?
    
    // MARK: Layout State
    
    var layoutState = LayoutState(
        state: .tip,
        initialScrollOffset: .zero,
        initialFrame: .zero,
        interactionInProgress: false,
        isRemovalInteractionEnabled: false,
        translationOffset: 0
    )
    
    // MARK: Scroll View State
    
    var scrollViewState = ScrollViewState(
        stopDeceleration: false,
        scrollIndicatorsVisible: false
    )

    // MARK: - Interface

    init(_ vc: FloatingPanelController, layout: FloatingPanelLayout, behavior: FloatingPanelBehavior) {
        viewcontroller = vc
        surfaceView = vc.view as! FloatingPanelSurfaceView
        backdropView = FloatingPanelBackdropView()
        backdropView.backgroundColor = .black
        backdropView.alpha = 0.0

        self.layoutAdapter = FloatingPanelLayoutAdapter(surfaceView: surfaceView,
                                                        backdropView: backdropView,
                                                        layout: layout)
        self.behavior = behavior

        panGesture = FloatingPanelPanGestureRecognizer()

        if #available(iOS 11.0, *) {
            panGesture.name = "FloatingPanelSurface"
        }

        super.init()

        surfaceView.addGestureRecognizer(panGesture)
        panGesture.addTarget(self, action: #selector(handle(panGesture:)))
        panGesture.delegate = self
    }

    func layoutViews(in vc: UIViewController) {
        unowned let view = vc.view!

        view.insertSubview(backdropView, belowSubview: surfaceView)
        backdropView.frame = view.bounds

        layoutAdapter.prepareLayout(toParent: vc)
    }

    func move(to: FloatingPanelPosition, animated: Bool, completion: (() -> Void)? = nil) {
        move(from: layoutState.state, to: to, animated: animated, completion: completion)
    }

    func present(animated: Bool, completion: (() -> Void)? = nil) {
        self.layoutAdapter.activateLayout(of: nil)
        move(from: nil, to: layoutAdapter.layout.initialPosition, animated: animated, completion: completion)
    }

    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        move(from: layoutState.state, to: nil, animated: animated, completion: completion)
    }

    private func move(from: FloatingPanelPosition?, to: FloatingPanelPosition?, animated: Bool, completion: (() -> Void)? = nil) {
        if to != .full {
            lockScrollView()
        }

        if animated {
            let animator: UIViewPropertyAnimator
            switch (from, to) {
            case (nil, let to?):
                animator = behavior.addAnimator(self.viewcontroller, to: to)
            case (let from?, let to?):
                animator = behavior.moveAnimator(self.viewcontroller, from: from, to: to)
            case (let from?, nil):
                animator = behavior.removeAnimator(self.viewcontroller, from: from)
            case (nil, nil):
                fatalError()
            }

            animator.addAnimations { [weak self] in
                guard let self = self else { return }

                self.updateLayout(to: to)
                if let to = to {
                    self.layoutState.state = to
                }
            }
            animator.addCompletion { _ in
                completion?()
            }
            animator.startAnimation()
        } else {
            self.updateLayout(to: to)
            if let to = to {
                self.layoutState.state = to
            }
            completion?()
        }
    }

    // MARK: - Layout update

    private func updateLayout(to target: FloatingPanelPosition?) {
        self.layoutAdapter.activateLayout(of: target)
    }
    
    func getBackdropAlpha(with translation: CGPoint, layoutState: inout LayoutState) -> CGFloat {
        let currentY = currentOrigin(
            layoutState.initialFrame, translation, &layoutState, layoutAdapter, scrollView!, self
        )
        
        let next = directionalPosition(with: translation, layoutState: &layoutState)
        let pre = redirectionalPosition(with: translation, layoutState: &layoutState)
        let nextY = layoutAdapter.positionY(for: next)
        let preY = layoutAdapter.positionY(for: pre)

        let nextAlpha = layoutAdapter.layout.backdropAlphaFor(position: next)
        let preAlpha = layoutAdapter.layout.backdropAlphaFor(position: pre)

        if preY == nextY {
            return preAlpha
        } else {
            return preAlpha + max(min(1.0, 1.0 - (nextY - currentY) / (nextY - preY) ), 0.0) * (nextAlpha - preAlpha)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGesture else { return false }

        log.debug("shouldRecognizeSimultaneouslyWith", otherGestureRecognizer)

        return otherGestureRecognizer == scrollView?.panGestureRecognizer
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGesture else { return false }

        // Do not begin any gestures excluding the tracking scrollView's pan gesture until the pan gesture fails
        if otherGestureRecognizer == scrollView?.panGestureRecognizer {
            return false
        } else {
            return true
        }
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGesture else { return false }

        // Do not begin the pan gesture until any other gestures fail except fo the tracking scrollView's pan gesture.
        switch otherGestureRecognizer {
        case scrollView?.panGestureRecognizer:
            return false
        case is UIPanGestureRecognizer,
             is UISwipeGestureRecognizer,
             is UIRotationGestureRecognizer,
             is UIScreenEdgePanGestureRecognizer,
             is UIPinchGestureRecognizer:
            return true
        default:
            return false
        }
    }

    // MARK: - Gesture handling

    @objc func handle(panGesture: UIPanGestureRecognizer) {
        log.debug("Gesture >>>>", panGesture)
        
        switch panGesture {
        case scrollView?.panGestureRecognizer:
            ScrollViewGestureRecognition.willUpdate(
                scrollView!, surfaceView, layoutAdapter, layoutState
            )
        case panGesture:
            PanGestureRecognition.onUpdate(
                panGesture,
                scrollView!,
                &layoutState,
                self,
                PanGestureRecognition.shouldAllowScrollViewGestureRecognition,
                &scrollViewState
            )
        default:
            return
        }
    }

    func startRemovalAnimation(with translation: CGPoint, velocity: CGPoint, distance: CGFloat) -> Bool {
        let posY = layoutAdapter.positionY(for: layoutState.state)
        let currentY = currentOrigin(
            layoutState.initialFrame, translation, &layoutState, layoutAdapter, scrollView!, self
        )
        let safeAreaBottomY = layoutAdapter.safeAreaBottomY
        let vth = behavior.removalVelocity
        let pth = max(min(behavior.removalProgress, 1.0), 0.0)
        let velocityVector = (distance != 0) ? CGVector(dx: 0, dy: max(min(velocity.y/distance, vth), 0.0)) : .zero

        guard (safeAreaBottomY - posY) != 0 else { return false }
        guard (currentY - posY) / (safeAreaBottomY - posY) >= pth || velocityVector.dy == vth else { return false }

        viewcontroller.delegate?.floatingPanelDidEndDraggingToRemove(viewcontroller, withVelocity: velocity)
        let animator = self.behavior.removalInteractionAnimator(self.viewcontroller, with: velocityVector)
        animator.addAnimations { [weak self] in
            guard let self = self else { return }
            self.updateLayout(to: nil)
        }
        animator.addCompletion({ [weak self] (_) in
            guard let self = self else { return }
            self.viewcontroller.removePanelFromParent(animated: false)
            self.viewcontroller.delegate?.floatingPanelDidEndRemove(self.viewcontroller)
        })
        animator.startAnimation()
        return true
    }

    private func startInteraction(with translation: CGPoint) {
        log.debug("startInteraction")
        layoutState.initialFrame = surfaceView.frame
        if let scrollView = scrollView {
            layoutState.initialScrollOffset = scrollView.contentOffset
        }
        layoutState.translationOffset = translation.y
        viewcontroller.delegate?.floatingPanelWillBeginDragging(viewcontroller)

        lockScrollView()

        layoutState.interactionInProgress = true
    }

    func endInteraction(for targetPosition: FloatingPanelPosition, layoutState: inout LayoutState) {
        log.debug("endInteraction for \(targetPosition)")
        if targetPosition != .full {
            lockScrollView()
        }
        layoutState.interactionInProgress = false
    }

    var currentOrigin: (CGRect, CGPoint, inout LayoutState, FloatingPanelLayoutAdapter, UIScrollView, FloatingPanel) -> CGFloat {
        get {
            return {
                let dy = $1.y - $2.translationOffset
                let y = $0.offsetBy(dx: 0.0, dy: dy).origin.y
                
                let topY = $3.topY
                let topBuffer = $3.layout.topInteractionBuffer
                let bottomY = $3.bottomY
                let bottomBuffer = $3.layout.bottomInteractionBuffer
                
                if $4.panGestureRecognizer.state == .changed {
                    let preY = $5.surfaceView.frame.origin.y
                    if preY > 0 && preY > y {
                        return max(topY, min(bottomY, y))
                    }
                }
                return max(topY - topBuffer, min(bottomY + bottomBuffer, y))
            }
        }
    }
    
    func startAnimation(to targetPosition: FloatingPanelPosition, at distance: CGFloat, with velocity: CGPoint, layoutState: inout LayoutState) {
        var _layoutState = layoutState
        let targetY = layoutAdapter.positionY(for: targetPosition)
        let velocityVector = (distance != 0) ? CGVector(dx: 0, dy: max(min(velocity.y/distance, 30.0), -30.0)) : .zero
        let animator = behavior.interactionAnimator(self.viewcontroller, to: targetPosition, with: velocityVector)
        animator.isInterruptible = false // To prevent a backdrop color's punk
        animator.addAnimations { [weak self] in
            guard let self = self else { return }
            if _layoutState.state == targetPosition {
                self.surfaceView.frame.origin.y = targetY
                self.layoutAdapter.setBackdropAlpha(of: targetPosition)
            } else {
                self.updateLayout(to: targetPosition)
            }
            _layoutState.state = targetPosition
        }
        animator.addCompletion { [weak self] pos in
            guard let self = self else { return }
            guard
                _layoutState.interactionInProgress == false,
                animator == self.animator,
                pos == .end
                else { return }
            self.finishAnimation(at: targetPosition)
        }
        animator.startAnimation()
        self.animator = animator
    }

    private func finishAnimation(at targetPosition: FloatingPanelPosition) {
        log.debug("finishAnimation \(targetPosition)")
        self.animator = nil
        self.viewcontroller.delegate?.floatingPanelDidEndDecelerating(self.viewcontroller)

        scrollViewState.stopDeceleration = false
        // Don't unlock scroll view in animating view when presentation layer != model layer
        unlockScrollView()
    }

    func distance(to targetPosition: FloatingPanelPosition, with translation: CGPoint, layoutState: inout LayoutState) -> CGFloat {
        let topY = layoutAdapter.topY
        let middleY = layoutAdapter.middleY
        let bottomY = layoutAdapter.bottomY
        let currentY = currentOrigin(
            layoutState.initialFrame, translation, &layoutState, layoutAdapter, scrollView!, self
        )
        switch targetPosition {
        case .full:
            return CGFloat(fabs(Double(currentY - topY)))
        case .half:
            return CGFloat(fabs(Double(currentY - middleY)))
        case .tip:
            return CGFloat(fabs(Double(currentY - bottomY)))
        }
    }

    private func directionalPosition(with translation: CGPoint, layoutState: inout LayoutState) -> FloatingPanelPosition {
        let currentY = currentOrigin(
            layoutState.initialFrame, translation, &layoutState, layoutAdapter, scrollView!, self
        )
        
        let supportedPositions: Set = layoutAdapter.layout.supportedPositions

        if supportedPositions.count == 1 {
            return layoutState.state
        }

        switch supportedPositions {
        case [.full, .half]: return translation.y >= 0 ? .half : .full
        case [.half, .tip]: return translation.y >= 0 ? .tip : .half
        case [.full, .tip]: return translation.y >= 0 ? .tip : .full
        default:
            let middleY = layoutAdapter.middleY

            switch layoutState.state {
            case .full:
                if translation.y <= 0 {
                    return .full
                }
                return currentY > middleY ? .tip : .half
            case .half:
                return translation.y >= 0 ? .tip : .full
            case .tip:
                if translation.y >= 0 {
                    return .tip
                }
                return currentY > middleY ? .half : .full
            }
        }
    }

    private func redirectionalPosition(with translation: CGPoint, layoutState: inout LayoutState) -> FloatingPanelPosition {
        let currentY = currentOrigin(
            layoutState.initialFrame, translation, &layoutState, layoutAdapter, scrollView!, self
        )

        let supportedPositions: Set = layoutAdapter.layout.supportedPositions

        if supportedPositions.count == 1 {
            return layoutState.state
        }

        switch supportedPositions {
        case [.full, .half]: return translation.y >= 0 ? .full : .half
        case [.half, .tip]: return translation.y >= 0 ? .half : .tip
        case [.full, .tip]: return translation.y >= 0 ? .full : .tip
        default:
            let middleY = layoutAdapter.middleY

            switch layoutState.state {
            case .full:
                return currentY > middleY ? .half : .full
            case .half:
                return .half
            case .tip:
                return currentY > middleY ? .tip : .half
            }
        }
    }

    // Distance travelled after decelerating to zero velocity at a constant rate.
    // Refer to the slides p176 of [Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/)
    private func project(initialVelocity: CGFloat) -> CGFloat {
        let decelerationRate = UIScrollView.DecelerationRate.normal.rawValue
        return (initialVelocity / 1000.0) * decelerationRate / (1.0 - decelerationRate)
    }

    func targetPosition(with translation: CGPoint, velocity: CGPoint, layoutState: inout LayoutState) -> (FloatingPanelPosition) {
        let currentY = currentOrigin(
            layoutState.initialFrame, translation, &layoutState, layoutAdapter, scrollView!, self
        )
        let supportedPositions: Set = layoutAdapter.layout.supportedPositions

        if supportedPositions.count == 1 {
            return layoutState.state
        }

        switch supportedPositions {
        case [.full, .half]:
            return targetPosition(from: [.full, .half], at: currentY, velocity: velocity)
        case [.half, .tip]:
            return targetPosition(from: [.half, .tip], at: currentY, velocity: velocity)
        case [.full, .tip]:
            return targetPosition(from: [.full, .tip], at: currentY, velocity: velocity)
        default:
            /*
             [topY|full]---[th1]---[middleY|half]---[th2]---[bottomY|tip]
             */
            let topY = layoutAdapter.topY
            let middleY = layoutAdapter.middleY
            let bottomY = layoutAdapter.bottomY

            let target: FloatingPanelPosition
            let forwardYDirection: Bool

            switch layoutState.state {
            case .full:
                target = .half
                forwardYDirection = true
            case .half:
                if (currentY < middleY) {
                    target = .full
                    forwardYDirection = false
                } else {
                    target = .tip
                    forwardYDirection = true
                }
            case .tip:
                target = .half
                forwardYDirection = false
            }

            let redirectionalProgress = max(min(behavior.redirectionalProgress(viewcontroller, from: layoutState.state, to: target), 1.0), 0.0)

            let th1: CGFloat
            let th2: CGFloat

            if forwardYDirection {
                th1 = topY + (middleY - topY) * redirectionalProgress
                th2 = middleY + (bottomY - middleY) * redirectionalProgress
            } else {
                th1 = middleY - (middleY - topY) * redirectionalProgress
                th2 = bottomY - (bottomY - middleY) * redirectionalProgress
            }

            switch currentY {
            case ..<th1:
                if project(initialVelocity: velocity.y) >= (middleY - currentY) {
                    return .half
                } else {
                    return .full
                }
            case ...middleY:
                if project(initialVelocity: velocity.y) <= (topY - currentY) {
                    return .full
                } else {
                    return .half
                }
            case ..<th2:
                if project(initialVelocity: velocity.y) >= (bottomY - currentY) {
                    return .tip
                } else {
                    return .half
                }
            default:
                if project(initialVelocity: velocity.y) <= (middleY - currentY) {
                    return .half
                } else {
                    return .tip
                }
            }
        }
    }

    private func targetPosition(from positions: [FloatingPanelPosition], at currentY: CGFloat, velocity: CGPoint) -> FloatingPanelPosition {
        assert(positions.count == 2)

        let top = positions[0]
        let bottom = positions[1]

        let topY = layoutAdapter.positionY(for: top)
        let bottomY = layoutAdapter.positionY(for: bottom)

        let target = top == layoutState.state ? bottom : top
        let redirectionalProgress = max(min(behavior.redirectionalProgress(viewcontroller, from: layoutState.state, to: target), 1.0), 0.0)

        let th = topY + (bottomY - topY) * redirectionalProgress

        switch currentY {
        case ..<th:
            if project(initialVelocity: velocity.y) >= (bottomY - currentY) {
                return bottom
            } else {
                return top
            }
        default:
            if project(initialVelocity: velocity.y) <= (topY - currentY) {
                return top
            } else {
                return bottom
            }
        }
    }

    // MARK: - ScrollView handling

    func lockScrollView() {
        guard let scrollView = scrollView else { return }

        scrollView.isDirectionalLockEnabled = true
        scrollView.showsVerticalScrollIndicator = false
    }

    func unlockScrollView() {
        guard let scrollView = scrollView else { return }

        scrollView.isDirectionalLockEnabled = false
        scrollView.showsVerticalScrollIndicator = scrollViewState.scrollIndicatorsVisible
    }


    // MARK: - UIScrollViewDelegate Intermediation
    override func responds(to aSelector: Selector!) -> Bool {
        return super.responds(to: aSelector) || userScrollViewDelegate?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if userScrollViewDelegate?.responds(to: aSelector) == true {
            return userScrollViewDelegate
        } else {
            return super.forwardingTarget(for: aSelector)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if layoutState.state != .full {
            layoutState.initialScrollOffset = scrollView.contentOffset
        }
        userScrollViewDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        if scrollViewState.stopDeceleration {
            targetContentOffset.pointee = scrollView.contentOffset
            scrollViewState.stopDeceleration = false
        } else {
            userScrollViewDelegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
        }
    }
}
