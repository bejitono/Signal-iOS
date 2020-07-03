//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit
import LightningKitUI

@objc
public class OnboardingRecoveryPhraseViewController: OnboardingBaseViewController {
    
    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.titleLabel(text: "Recovery Phrase") // TODO: Localization
        titleLabel.accessibilityIdentifier = "onboarding.permissions." + "titleLabel"

        let explanationLabel = self.explanationLabel(explanationText: "This seed phrase enables you to recover the keys to your funds. Please write down your seed phrase in a safe place. You won't be able to access this seed phrase after you proceed from this screen.")  // TODO: Localize
        explanationLabel.accessibilityIdentifier = "onboarding.recoveryPhrase." + "explanationLabel"
        
        let seedView = SeedListView(seed: ["GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT", "GOAT"]) // TODO: Get list from LK

        let setupWalletButton = self.primaryButton(title: "Setup wallet",
                                                  selector: #selector(setupWalletPressed))
        setupWalletButton.accessibilityIdentifier = "onboarding.recoveryPhrase." + "setupWalletButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: setupWalletButton)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 20),
            explanationLabel,
            UIView.spacer(withHeight: 20),
            seedView,
            UIView.spacer(withHeight: 20),
            primaryButtonView
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 0
        primaryView.addSubview(stackView)

        stackView.autoPinEdgesToSuperviewMargins()
    }

     // MARK: - Events

     @objc func setupWalletPressed() {
         Logger.info("")
         // TODO: onboardingController to finish wallet setup
        print("Finish wallet setup")
     }
}
