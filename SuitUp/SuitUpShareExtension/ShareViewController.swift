//
//  ShareViewController.swift
//  SuitUpShareExtension
//
//  Hosts a SwiftUI view that lets the user route a shared image/URL into one
//  of the main app's flows. Writes a manifest + (optional) image file to the
//  App Group inbox; the main app picks it up on next foreground.
//

import UIKit
import SwiftUI

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let inputItems = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []

        let host = UIHostingController(
            rootView: ShareRouterView(
                inputItems: inputItems,
                onDone: { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                },
                onCancel: { [weak self] in
                    let err = NSError(domain: "dev.fisommer.SuitUp.share", code: 0, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])
                    self?.extensionContext?.cancelRequest(withError: err)
                }
            )
        )

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }
}
