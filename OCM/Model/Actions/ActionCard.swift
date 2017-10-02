//
//  ActionCard.swift
//  OCM
//
//  Created by Carlos Vicente on 21/3/17.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import Foundation
import GIGLibrary

struct ActionCard: Action {
    
    var output: ActionOut?
    let cards: [Card]
    internal var identifier: String?
    internal var preview: Preview?
    internal var shareInfo: ShareInfo?
    internal var actionView: OrchextraViewController?
    
    static func action(from json: JSON) -> Action? {
        guard
            json["type"]?.toString() == ActionType.actionCard,
            let render = json["render"]?.toDictionary(),
            let renderElements = render["elements"] as? [NSDictionary]
            else {
                return nil
        }
        var cards: [Card] = []
        for renderElement in renderElements {
            guard let cardsElements = renderElement["elements"] as? [NSDictionary] else { return nil }
            for card in cardsElements {
                guard let cardComponents = card["elements"] as? [NSDictionary] else { return nil }
                if let card = Card.card(from: JSON(from: cardComponents)) {
                    cards.append(card)
                }
            }
        }
        return ActionCard(
            output: nil,
            cards: cards,
            identifier: nil,
            preview: preview(from: json),
            shareInfo: shareInfo(from: json),
            actionView: OCM.shared.wireframe.showCards(cards)
        )
    }
    
    func view() -> OrchextraViewController? {
        return self.actionView
    }
    
    func run(viewController: UIViewController?) {
        guard let fromVC = viewController else {
            return
        }
        OCM.shared.wireframe.showMainComponent(with: self, viewController: fromVC)
    }
}
