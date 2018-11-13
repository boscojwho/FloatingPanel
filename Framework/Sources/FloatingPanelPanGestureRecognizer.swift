//
//  FloatingPanelPanGestureRecognizer.swift
//  FloatingPanel
//
//  Created by BozBook on 2018-11-12.
//  Copyright © 2018 scenee. All rights reserved.
//

import UIKit

class FloatingPanelPanGestureRecognizer: UIPanGestureRecognizer {
    override weak var delegate: UIGestureRecognizerDelegate? {
        get {
            return super.delegate
        }
        set {
            guard newValue is FloatingPanel else {
                let exception = NSException(name: .invalidArgumentException,
                                            reason: "FloatingPanelController's built-in pan gesture recognizer must have its controller as its delegate.",
                                            userInfo: nil)
                exception.raise()
                return
            }
            super.delegate = newValue
        }
    }
}
