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
        return CGRect(x: max(0,containerView.bounds.midX - min(size.width, containerView.bounds.width - 16)/2), y: containerView.bounds.maxY - size.height - containerView.safeAreaInsets.bottom, width: min(size.width, containerView.bounds.width - 16), height: size.height)
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
