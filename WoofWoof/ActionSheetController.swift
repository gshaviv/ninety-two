//
//  ActionSheetController.swift
//  WoofWoof
//
//  Created by Guy on 12/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit



class ActionSheetController: UIViewController, UIViewControllerTransitioningDelegate {

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return ActionAnimator(presenting: false)
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return ActionAnimator(presenting: true)
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return ActionPresenter(presentedViewController: presented, presenting: presenting)
    }

    private func commonInit() {
        self.transitioningDelegate = self
        self.modalPresentationStyle = .custom
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
}

private class ActionPresenter: UIPresentationController {
    var dimmingView: UIView = {
        let d = UIView()
        d.backgroundColor = UIColor(white: 0, alpha: 0.4)
        d.tag = 131
        return d
    }()
    private var keyboardTopInContainr: CGFloat = CGFloat.greatestFiniteMagnitude

    override init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        super.init(presentedViewController: presentedViewController, presenting: presentingViewController)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        observe(presentedViewController, keypath: \.preferredContentSize) { [weak self] (vc, _) in
            guard let self = self else {
                return
            }
            UIView.animate(withDuration: 0.25) {
                self.presentedViewController.view.frame = self.frameOfPresentedViewInContainerView
            }
        }
    }

    @objc private func keyboardFrameWillChange(_ note: Notification?) {
        let keyboardFrame = (note?.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue

        if let keyboardFrame = keyboardFrame, let containerView = containerView {
            keyboardTopInContainr = containerView.convert(keyboardFrame, from: containerView.window).minY

            var duration = (note?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.3
            if duration == 0 && !((note?.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue ?? true) {
                duration = 0.25
            }

            let curveValue = (note?.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
            let options: UIView.AnimationOptions = [UIView.AnimationOptions(rawValue: curveValue), .beginFromCurrentState]

            UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
                self.presentedViewController.view.frame = self.frameOfPresentedViewInContainerView
            }, completion: nil)
        }
    }

    @objc private func dimiss() {
        presentedViewController.dismiss(animated: true, completion: nil)
    }

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else {
            return
        }
        containerView.addSubview(dimmingView)
        dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimiss)))
        dimmingView.frame = containerView.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmingView.alpha = 0
        if let transitionCoordinator = presentingViewController.transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: { (_: UIViewControllerTransitionCoordinatorContext!) -> Void in
                self.dimmingView.alpha = 1.0
            }, completion: nil)
        }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            dimmingView.removeFromSuperview()
        }
    }

    override func dismissalTransitionWillBegin() {
        if let transitionCoordinator = presentingViewController.transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: { (_: UIViewControllerTransitionCoordinatorContext!) -> Void in
                self.dimmingView.alpha = 0
            }, completion: nil)
        }
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView = containerView else {
            return .zero
        }
        _ = presentedViewController.view
        let size = presentedViewController.preferredContentSize == .zero ? presentedViewController.view.frame.size : presentedViewController.preferredContentSize
        return CGRect(x: max(0,containerView.bounds.midX - min(size.width, containerView.bounds.width - 16)/2), y: max(min(containerView.bounds.maxY - size.height - containerView.safeAreaInsets.bottom, keyboardTopInContainr - size.height )
            ,containerView.safeAreaInsets.top), width: min(size.width, containerView.bounds.width - 16), height: size.height)
    }
}


private class ActionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isPresenting: Bool
    let duration: TimeInterval = 0.3

    @objc required init(presenting: Bool) {
        isPresenting = presenting

        super.init()
    }

    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval {
        return duration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let presentedController = transitionContext.viewController(forKey: isPresenting ? UITransitionContextViewControllerKey.to : UITransitionContextViewControllerKey.from)!
        let presentedControllerView = presentedController.view!
        presentedControllerView.clipsToBounds = true
        presentedControllerView.layer.cornerRadius = 8
        let containerView = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: presentedController)
        let initialFrame = CGRect(origin: CGPoint(x: finalFrame.origin.x, y: containerView.height), size: finalFrame.size)
        if isPresenting {
            presentedControllerView.frame = initialFrame
            containerView.addSubview(presentedControllerView)

            UIView.animate(withDuration: duration, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 1.0, options: UIView.AnimationOptions.curveLinear, animations: { () -> Void in
                presentedControllerView.frame = finalFrame
            }, completion: { completed in
                transitionContext.completeTransition(completed)
            })
        } else {
            UIView.animate(withDuration: duration, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.0, options: UIView.AnimationOptions.curveLinear, animations: { () -> Void in
                presentedControllerView.frame = initialFrame
            }, completion: { (completed: Bool) in
                transitionContext.completeTransition(completed)
            })
        }
    }
}
