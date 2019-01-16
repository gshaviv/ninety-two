//
//  PDFViewerViewController.swift
//  PDFCreation
//
//  Created by Guy on 12/01/2019.
//  Copyright © 2019 TivStudio. All rights reserved.
//

import UIKit
import PDFKit

open class PDFViewerViewController: UIViewController {
    @IBOutlet var toolbar: UIToolbar!
    @IBOutlet var pdfView: PDFView!
    var document: PDFDocument? {
        didSet {
            pdfView.document = document
        }
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        pdfView.document = document
        pdfView.displayDirection = .horizontal
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.backgroundColor = UIColor(white: 0.5, alpha: 1)

        if let title = document?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            navigationItem.title = title
        } else {
            navigationItem.title = "PDF"
        }


        let bundle = Bundle(for: type(of: self))
        let space = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        space.width = 20
        toolbar.items = [
            UIBarButtonItem(image: UIImage(named: "prev", in: bundle, compatibleWith: nil), style: .plain, target: self, action: #selector(prevPage)),
            space,
            UIBarButtonItem(image: UIImage(named: "next", in: bundle, compatibleWith: nil), style: .plain, target: self, action: #selector(nextPage))
        ]

        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "share", in: bundle, compatibleWith: nil), style: .plain, target: self, action: #selector(share))
        if presentingViewController != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        }

    }

    public init(doc: PDFDocument) {
        document = doc
        super.init(nibName: nil, bundle: Bundle(for: type(of: self)))
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    @objc private func  nextPage() {
        if pdfView.canGoToNextPage() {
            pdfView.goToNextPage(nil)
        }
    }

    @objc private func prevPage() {
        if pdfView.canGoToPreviousPage() {
            pdfView.goToPreviousPage(nil)
        }
    }

    @objc private func share() {
        guard let document = document else {
            return
        }
        var items = [Any]()
        if let url = document.documentURL {
            items.append(url)
        } else if let data = document.dataRepresentation() {
            items.append(data)
        }
        if !items.isEmpty {
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
        }
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
}

extension PDFViewerViewController {
    public class func controller(for doc: PDFDocument) -> UIViewController {
        let ctr = PDFViewerViewController(doc: doc)
        let nav = UINavigationController(rootViewController: ctr)
        return nav
    }
}
