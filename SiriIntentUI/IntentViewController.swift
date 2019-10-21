//
//  IntentViewController.swift
//  SiriIntentUI
//
//  Created by Guy on 12/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import IntentsUI

// As an example, this extension's Info.plist has been configured to handle interactions for INSendMessageIntent.
// You will want to replace this or add other intents as appropriate.
// The intents whose interactions you wish to handle must be declared in the extension's Info.plist.

// You can test this example integration by saying things to Siri like:
// "Send a message using <myApp>"

class IntentViewController: UIViewController, INUIHostedViewControlling {
    var contentVC: TodayViewController?
    var callback: ((Bool, Set<INParameter>, CGSize) -> Void)?
    var done = false
        
    // MARK: - INUIHostedViewControlling
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    // Prepare your view controller for the interaction to handle.
    func configureView(for parameters: Set<INParameter>, of interaction: INInteraction, interactiveBehavior: INUIInteractiveBehavior, context: INUIHostedViewContext, completion: @escaping (Bool, Set<INParameter>, CGSize) -> Void) {
        // Do configuration here, including preparing views and calculating a desired size for presentation.
        if done {
            completion(true, parameters, self.desiredSize)
        } else {
            callback = completion
        }
    }
    
    var desiredSize: CGSize {
        if var size = self.extensionContext?.hostedViewMaximumAllowedSize {
            size.height = min(size.height, 250)
            return size
        }
        return CGSize(width: UIScreen.main.bounds.width - 40, height: 250)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let ctr = segue.destination as? TodayViewController {
            contentVC = ctr
            ctr.widgetPerformUpdate { (_) in
                self.done = true
                ctr.widgetActiveDisplayModeDidChange(.expanded, withMaximumSize: self.desiredSize)
                self.callback?(true, [], self.desiredSize)
            }
        }
    }
    
}
