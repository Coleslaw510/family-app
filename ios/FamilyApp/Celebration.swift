import SpriteKit
import SwiftUI
import UIKit

final class ConfettiScene: SKScene {
    private let palette: [UIColor] = [
        UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1),
        UIColor(red: 0.745, green: 0.094, blue: 0.365, alpha: 1),
        UIColor(red: 0.051, green: 0.580, blue: 0.533, alpha: 1),
        UIColor(red: 0.918, green: 0.345, blue: 0.047, alpha: 1),
        UIColor(red: 0.486, green: 0.227, blue: 0.929, alpha: 1),
        UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)
    ]

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill
        physicsWorld.gravity = CGVector(dx: 0, dy: -2.6)
        let width = max(size.width, 320)
        let height = max(size.height, 640)
        for _ in 0..<100 {
            let pieceWidth = CGFloat.random(in: 6...11)
            let pieceHeight = CGFloat.random(in: 8...14)
            let node = SKShapeNode(rectOf: CGSize(width: pieceWidth, height: pieceHeight), cornerRadius: 2)
            node.fillColor = palette.randomElement() ?? .white
            node.strokeColor = .clear
            node.position = CGPoint(x: CGFloat.random(in: 0...width), y: height + CGFloat.random(in: 0...160))
            let body = SKPhysicsBody(rectangleOf: CGSize(width: pieceWidth, height: pieceHeight))
            body.collisionBitMask = 0
            body.linearDamping = CGFloat.random(in: 0.15...0.7)
            body.angularVelocity = CGFloat.random(in: -5...5)
            body.velocity = CGVector(dx: CGFloat.random(in: -60...60), dy: CGFloat.random(in: -20...40))
            node.physicsBody = body
            addChild(node)
        }
    }
}

final class SparkleScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill
        let spawn = SKAction.run { [weak self] in self?.spawn() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 0.16)])))
    }

    private func spawn() {
        let node = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.4...2.8))
        node.fillColor = UIColor(red: 0.918, green: 0.345, blue: 0.047, alpha: 0.85)
        node.strokeColor = .clear
        let width = max(size.width, 80)
        let height = max(size.height, 70)
        node.position = CGPoint(x: width / 2 + CGFloat.random(in: -22...22), y: 6)
        addChild(node)
        let rise = SKAction.group([
            .moveBy(x: CGFloat.random(in: -14...14), y: height * 0.85, duration: 1.35),
            .fadeOut(withDuration: 1.35),
            .scale(to: 0.2, duration: 1.35)
        ])
        node.run(.sequence([rise, .removeFromParent()]))
    }
}

struct CelebrationOverlay: View {
    var title: String
    @State private var scene: SKScene = {
        let scene = ConfettiScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        return scene
    }()

    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: scene, options: [.allowsTransparency])
                .ignoresSafeArea()
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .shadow(color: Color(hex: 0x0F172A).opacity(0.08), radius: 8, y: 4)
                .padding(.top, 72)
        }
        .allowsHitTesting(false)
    }
}

struct SparkleCountdown: View {
    var days: Int
    var label: String = "DAYS"
    @State private var scene: SKScene = {
        let scene = SparkleScene(size: CGSize(width: 88, height: 72))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        return scene
    }()

    var body: some View {
        ZStack {
            SpriteView(scene: scene, options: [.allowsTransparency])
            VStack(spacing: 0) {
                Text("\(days)")
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.vacation)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 88, height: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(days) \(label.lowercased())")
    }
}
