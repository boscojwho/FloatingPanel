//
//  GestureRecognition.swift
//  FloatingPanel
//
//  Created by BozBook on 2018-11-11.
//  Copyright © 2018 scenee. All rights reserved.
//

import UIKit

class GestureRecognition: NSObject {
    
    let scrollView: UIScrollView
    let panGestureRecognizer: UIPanGestureRecognizer
    
    required init(scrollView: UIScrollView, panGestureRecognizer: UIPanGestureRecognizer) {
        self.scrollView = scrollView
        self.panGestureRecognizer = panGestureRecognizer
    }
    
    @objc func panGestureRecognizer(didUpdate: UIPanGestureRecognizer) {
        
    }
}

struct LayoutState {
    
    var state = FloatingPanelPosition.tip
    var isBottomState: (FloatingPanelLayoutAdapter) -> Bool {
        get {
            return {
                let remains = $0.layout.supportedPositions.filter { $0.rawValue > self.state.rawValue }
                return remains.count == 0
            }
        }
    }
    
    var initialScrollOffset = CGPoint.zero
    var initialFrame = CGRect.zero
    
    var interactionInProgress = false
    var isRemovalInteractionEnabled = false
    
    /// - Note: Originally named `translationOffsetY`.
    var translationOffset: CGFloat = 0
}

struct ScrollViewState {
    
    var stopDeceleration = false
    var scrollIndicatorsVisible = false
}

struct PanGestureRecognition {
    
    /// Call before switching into UIGestureRecognizer.state-specific update actions.
    static var onUpdate: (UIPanGestureRecognizer, UIScrollView, inout LayoutState, FloatingPanel, AllowScrollViewGestureRecognition, inout ScrollViewState) -> () {
        get {
            return {
                guard $4($1, $0, $2, $3) == false else {
                    return
                }
                
                switch $0.state {
                case .began:
                    onBegan($0)
                case .changed:
                    onChanged($0, &$2, $3)
                case .ended, .cancelled, .failed:
                    onEnded($0, &$2, &$5, $3, $3.layoutAdapter)
                case .possible:
                    break
                }
            }
        }
    }
    
    static var onBegan: (UIPanGestureRecognizer) -> () {
        get {
            return { _ in
                // A user interaction does not always start from Began state of the pan gesture
                // because it can be recognized in scrolling a content in a content view controller.
                // So do nothing here.
                log.debug("panningBegan")
            }
        }
    }
    
    static var onChanged: (UIPanGestureRecognizer, inout LayoutState, FloatingPanel) -> () {
        get {
            return {
                log.debug("panningChange")
                
                let translation = $0.translation(in: $0.view!.superview)
                let currentY = $2.currentOrigin(
                    $1.initialFrame, translation, $1, $2.layoutAdapter, $2.scrollView!, $2
                )
                
                var frame = $1.initialFrame
                frame.origin.y = currentY
                $2.surfaceView.frame = frame
                $2.backdropView.alpha = $2.getBackdropAlpha(with: translation, layoutState: &$1)
                
                $2.viewcontroller.delegate?.floatingPanelDidMove($2.viewcontroller)
            }
        }
    }
    
    static var onEnded: (UIPanGestureRecognizer, inout LayoutState, inout ScrollViewState, FloatingPanel, FloatingPanelLayoutAdapter) -> () {
        get {
            return {
                log.debug("panningEnd")
                
                let translation = $0.translation(in: $0.view!.superview)
                let velocity = $0.velocity(in: $0.view)
                
                if $1.interactionInProgress == false {
                    $1.initialFrame = $3.surfaceView.frame
                }
                
                // Projecting the dragging to the scroll dragging or not
                $2.stopDeceleration = ($3.surfaceView.frame.minY > $4.topY)
                
                let targetPosition = $3.targetPosition(with: translation, velocity: velocity, layoutState: &$1)
                let distance = $3.distance(to: targetPosition, with: translation, layoutState: &$1)
                
                $3.endInteraction(for: targetPosition, layoutState: &$1)
                
                if $1.isRemovalInteractionEnabled, $1.isBottomState($4) {
                    if $3.startRemovalAnimation(with: translation, velocity: velocity, distance: distance) {
                        return
                    }
                }
                
                $3.viewcontroller.delegate?.floatingPanelDidEndDragging($3.viewcontroller, withVelocity: velocity, targetPosition: targetPosition)
                $3.viewcontroller.delegate?.floatingPanelWillBeginDecelerating($3.viewcontroller)
                
                $3.startAnimation(to: targetPosition, at: distance, with: velocity, layoutState: &$1)
            }
        }
    }
    
    typealias AllowScrollViewGestureRecognition = (UIScrollView, UIPanGestureRecognizer, LayoutState, FloatingPanel) -> Bool
    
    static var shouldAllowScrollViewGestureRecognition: AllowScrollViewGestureRecognition {
        get {
            return {
                let location = $1.location(in: $1.view)
                let velocity = $1.velocity(in: $1.view)

                let grabberBarFrame = CGRect(
                    x: $3.surfaceView.bounds.origin.x,
                    y: $3.surfaceView.bounds.origin.y,
                    width: $3.surfaceView.bounds.width,
                    height: FloatingPanelSurfaceView.topGrabberBarHeight * 2
                )
                
                guard
                    $2.state == .full,                   // When not .full, don't scroll.
                    $2.interactionInProgress == false,   // When interaction already in progress, don't scroll.
                    $0.frame.contains(location), // When point not in scrollView, don't scroll.
                    !grabberBarFrame.contains(location)  // When point within grabber area, don't scroll.
                    else {
                        return false
                }
                
                if $0.contentOffset.y - $0.contentOffsetZero.y != 0 {
                    return true
                }
                if $0.isDecelerating {
                    return true
                }
                if velocity.y < 0 {
                    return true
                }
                
                return false
            }
        }
    }
}

struct ScrollViewGestureRecognition {
    
    static var willUpdate: (UIScrollView, FloatingPanelSurfaceView, FloatingPanelLayoutAdapter, LayoutState) -> () {
        get {
            return {
                // Prevent scroll slip by the top bounce.
                if $0.isDecelerating == false {
                    $0.bounces = ($0.contentOffset.y > 10.0)
                }
                
                if $1.frame.minY > $2.topY {
                    switch $3.state {
                    case .full:
                        // Prevent over scrolling from scroll top in moving the panel from full.
                        $0.contentOffset.y = $0.contentOffsetZero.y
                    case .half, .tip:
                        guard $0.isDecelerating == false else {
                            // Don't fix the scroll offset in animating the panel to half and tip.
                            // It causes a buggy scrolling deceleration because `state` becomes
                            // a target position in animating the panel on the interaction from full.
                            return
                        }
                        // Fix the scroll offset in moving the panel from half and tip.
                        $0.contentOffset.y = $3.initialScrollOffset.y
                    }
                }
            }
        }
    }
}
