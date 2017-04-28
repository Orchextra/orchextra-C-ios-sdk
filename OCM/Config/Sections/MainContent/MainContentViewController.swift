//
//  MainContentViewController.swift
//  OCM
//
//  Created by Judith Medina on 24/10/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit
import GIGLibrary

enum MainContentViewType {
    case preview
    case content
}

class MainContentViewController: ModalImageTransitionViewController, MainContentUI, UIScrollViewDelegate,
WebVCDelegate, PreviewViewDelegate, ImageTransitionZoomable {

    
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var imageView: UIImageView!

    let margin: CGFloat = 100.0
    
    var presenter: MainPresenter?
    var contentBelow: Bool = false
    var contentFinished: Bool = false
    var currentlyViewing: MainContentViewType = .preview
    var lastContentOffset: CGFloat = 0
    var action: Action?
    
    weak var previewView: PreviewView?
    weak var viewAction: OrchextraViewController?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.previewView?.previewWillDissapear()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.scrollView.delegate = self
        self.automaticallyAdjustsScrollViewInsets = false
        self.presenter?.viewIsReady()
        self.configureShareButton()
        // Add a gesture to dimiss the view
        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(didTap(backButton:)))
        swipeGesture.direction = .right
        self.view.addGestureRecognizer(swipeGesture)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.previewView?.previewDidAppear()
    }
    
    // MARK: Events
    
    @IBAction func didTap(share: UIButton) {
        self.presenter?.userDidShare()
    }
    
    @IBAction func didTap(backButton: UIButton) {
        self.viewAction?.removeFromParentViewController()
        self.hide()
    }
    
    // MARK: PMainContent
    
    func show(preview: Preview?, action: Action) {
        
        if (action.view()) != nil {
            self.contentBelow = true
        }
        
        self.action = action
        self.viewAction = action.view()
        
        if let previewView = preview?.display(), let preview = preview {
            self.previewView = previewView
            self.previewView?.delegate = self
            self.previewView?.behaviour = PreviewInteractionController.previewInteractionController(scroll: self.scrollView, previewView: previewView.show(), preview: preview, content: viewAction)
            self.currentlyViewing = .preview
            self.previewLoaded()
            self.stackView.addArrangedSubview(previewView.show())
        } else {
            self.currentlyViewing = .content
            self.contentLoaded()
        }
        
        if let viewAction = self.viewAction {
            
            if let webVC = viewAction as? WebVC {
                webVC.delegate = self
            }
            
            addChildViewController(viewAction)
            viewAction.didMove(toParentViewController: self)
            // Set the action view as least the view height
            viewAction.view.addConstraint(NSLayoutConstraint(
                item: viewAction.view,
                attribute: .height,
                relatedBy: .greaterThanOrEqual,
                toItem: nil,
                attribute: .notAnAttribute,
                multiplier: 1.0,
                constant: self.view.bounds.size.height
            ))
            self.stackView.addArrangedSubview(viewAction.view)
        }
    }
    
    func makeShareButtons(visible: Bool) {
        self.shareButton.isHidden = !visible
    }
    
    func share(_ info: ShareInfo) {

        var itemsToShare: [Any] = []
        
        if let text = info.text {
            itemsToShare.append(text)
        }
        
        if let urlString = info.url, let url = URL(string: urlString) {
            itemsToShare.append(url)
        }
        
        let activityViewController = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        self.present(activityViewController, animated: true)
    }
    
    // MARK: - UIScrollViewDelegate
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.updateFloatingButtons(scrollView: scrollView, isContentOwnScroll: false)
        self.previewView?.previewDidScroll(scroll: scrollView)
        // Check if changed from preview to content
        if let preview = self.previewView as? UIView, self.viewAction != nil {
            if scrollView.contentOffset.y == 0 {
                if self.currentlyViewing == .content {
                    self.currentlyViewing = .preview
                    // Notify that user is in preview
                    self.previewLoaded()
                }
            } else if scrollView.contentOffset.y >= preview.frame.size.height && self.currentlyViewing == .preview {
                self.currentlyViewing = .content
                // Notify that user is in content
                self.contentLoaded()
            }
        }
        // To check if scroll did end
        if !self.contentFinished && (scrollView.contentOffset.y >= (scrollView.contentSize.height - scrollView.frame.size.height)) {
            self.contentFinished = true
            self.presenter?.userDidFinishContent()
        }
    }
    
    // MARK: - WebVCDelegate
    
    func webViewDidScroll(_ webViewScroll: UIScrollView) {
        self.updateFloatingButtons(scrollView: webViewScroll, isContentOwnScroll: true)
        self.previewView?.previewDidScroll(scroll: webViewScroll)
    }
    
    // MARK: - PreviewDelegate
    
    func previewViewDidSelectShareButton() {
        self.presenter?.userDidShare()
    }
    
    func previewViewDidPerformBehaviourAction() {
        if !self.contentBelow {
             self.action?.executable()
        }
    }
    
    // MARK: - PRIVATE
    
    private func updateFloatingButtons(scrollView currentScroll: UIScrollView, isContentOwnScroll: Bool) {
        
        var shareButtonAlpha = self.shareButton.alpha
        shareButtonAlpha = self.alphaAccordingToDirection(forButton: shareButton, scroll: currentScroll)
        self.backButton.alpha = self.alphaAccordingToDirection(forButton: backButton, scroll: currentScroll)
        
        if let previewView = self.previewView?.show(), previewView.superview != nil {
            
            if !isContentOwnScroll {
                if previewView.superview != nil {
                    if currentScroll.contentOffset.y <= previewView.frame.size.height { // TOP Preview
                        backButton.alpha = 1
                    }
                    
                    if self.scrollView.contentOffset.y == previewView.frame.size.height {
                        shareButtonAlpha = 1
                    }
                }
                let offset =  1 - ((previewView.frame.size.height - self.scrollView.contentOffset.y) / 100)
                shareButtonAlpha = offset
            } else {
                if currentScroll.contentOffset.y < 0 { // TOP
                    shareButtonAlpha = 1
                }
            }
        }
        
        if currentScroll.contentOffset.y <= 0 { // TOP
            backButton.alpha = 1
        }
        
        self.shareButton.alpha = shareButtonAlpha
        
        self.lastContentOffset = currentScroll.contentOffset.y
    }
    
    private func alphaAccordingToDirection(forButton button: UIButton, scroll: UIScrollView) -> CGFloat {
        
        let contentOffset =  self.lastContentOffset
        var alpha: CGFloat = 0
        
        if contentOffset < scroll.contentOffset.y { // MOVE DOWN
            alpha = backButton.alpha > 0 ? backButton.alpha - 0.1 : 0
        } else { // MOVE UP
            alpha = backButton.alpha < 1 ? backButton.alpha + 0.1 : 1
        }
        
        if scroll.contentOffset.y + scroll.frame.size.height >= scroll.contentSize.height { // BOTOM Exeeded
            alpha = 0
        }
        
        return alpha
    }
    
    private func configureShareButton() {
        if let previewView = self.previewView?.show(), previewView.superview != nil {
            self.shareButton.alpha = 0
        } else {
            self.shareButton.alpha = 1
        }
    }
    
    private func previewLoaded() {
        if let actionIdentifier = self.action?.identifier {
            OCM.shared.analytics?.track(with: [
                AnalyticConstants.kAction: AnalyticConstants.kPreview,
                AnalyticConstants.kValue: actionIdentifier,
                AnalyticConstants.kContentType: AnalyticConstants.kPreview
            ])
        }
    }
    
    private func contentLoaded() {
        if let actionIdentifier = self.action?.identifier {
            OCM.shared.analytics?.track(with: [
                AnalyticConstants.kAction: AnalyticConstants.kContent,
                AnalyticConstants.kValue: actionIdentifier,
                AnalyticConstants.kContentType: Content.contentType(of: actionIdentifier) ?? ""
            ])
        }
    }
    
    // MARK: - ImageTransitionZoomable
    
    func createTransitionImageView() -> UIImageView {
        
        var imageView: UIImageView
        if let imagePreview = self.previewView?.imagePreview()?.image {
            imageView = UIImageView(image: imagePreview)
        } else {
            imageView = UIImageView(frame: self.view.frame)
            imageView.image = UIImage.OCM.colorPreviewView
        }
        imageView.contentMode = self.imageView.contentMode
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        imageView.frame = self.imageView!.frame
        return imageView
    }
    
    func presentationBefore() {
        self.imageView.isHidden = true
    }
    
    func presentationCompletion(completeTransition: Bool) {
        self.imageView.isHidden = false
    }
    
    func dismissalBeforeAction() {
        self.imageView.isHidden = true
    }
    
    func dismissalCompletionAction(completeTransition: Bool) {
        if !completeTransition {
            self.imageView.isHidden = false
        }
    }
}
