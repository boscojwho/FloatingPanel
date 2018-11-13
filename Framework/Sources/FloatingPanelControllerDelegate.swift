//
//  FloatingPanelControllerDelegate.swift
//  FloatingPanel
//
//  Created by BozBook on 2018-11-12.
//  Copyright © 2018 scenee. All rights reserved.
//

import UIKit

public protocol FloatingPanelControllerDelegate: class {
    // if it returns nil, FloatingPanelController uses the default layout
    func floatingPanel(_ vc: FloatingPanelViewController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout?
    
    // if it returns nil, FloatingPanelController uses the default behavior
    func floatingPanel(_ vc: FloatingPanelViewController, behaviorFor newCollection: UITraitCollection) -> FloatingPanelBehavior?
    
    func floatingPanelDidMove(_ vc: FloatingPanelViewController) // any offset changes
    
    // called on start of dragging (may require some time and or distance to move)
    func floatingPanelWillBeginDragging(_ vc: FloatingPanelViewController)
    // called on finger up if the user dragged. velocity is in points/second.
    func floatingPanelDidEndDragging(_ vc: FloatingPanelViewController, withVelocity velocity: CGPoint, targetPosition: FloatingPanelPosition)
    func floatingPanelWillBeginDecelerating(_ vc: FloatingPanelViewController) // called on finger up as we are moving
    func floatingPanelDidEndDecelerating(_ vc: FloatingPanelViewController) // called when scroll view grinds to a halt
    
    // called on start of dragging to remove its views from a parent view controller
    func floatingPanelDidEndDraggingToRemove(_ vc: FloatingPanelViewController, withVelocity velocity: CGPoint)
    // called when its views are removed from a parent view controller
    func floatingPanelDidEndRemove(_ vc: FloatingPanelViewController)
}

public extension FloatingPanelControllerDelegate {
    func floatingPanel(_ vc: FloatingPanelViewController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout? {
        return nil
    }
    func floatingPanel(_ vc: FloatingPanelViewController, behaviorFor newCollection: UITraitCollection) -> FloatingPanelBehavior? {
        return nil
    }
    func floatingPanelDidMove(_ vc: FloatingPanelViewController) {}
    func floatingPanelWillBeginDragging(_ vc: FloatingPanelViewController) {}
    func floatingPanelDidEndDragging(_ vc: FloatingPanelViewController, withVelocity velocity: CGPoint, targetPosition: FloatingPanelPosition) {}
    func floatingPanelWillBeginDecelerating(_ vc: FloatingPanelViewController) {}
    func floatingPanelDidEndDecelerating(_ vc: FloatingPanelViewController) {}
    
    func floatingPanelDidEndDraggingToRemove(_ vc: FloatingPanelViewController, withVelocity velocity: CGPoint) {}
    func floatingPanelDidEndRemove(_ vc: FloatingPanelViewController) {}
}
