import SwiftUI

/// Native Retina-crisp vector implementation of the MSNR Desk mark (200x200 coordinate space),
/// automatically adapting between the official Light-bg and Dark-bg brand palettes.
struct MSNRLogoMark: View {
    let isDark: Bool
    var showSacredGrid: Bool = true

    private static let cubeCenters: [(CGFloat, CGFloat)] = [
        (100, 100),
        (100, 64), (68.82, 82), (68.82, 118), (100, 136), (131.18, 118), (131.18, 82),
        (100, 28), (37.65, 64), (37.65, 136), (100, 172), (162.35, 136), (162.35, 64)
    ]

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 200.0
            let ox = (size.width - 200.0 * s) * 0.5
            let oy = (size.height - 200.0 * s) * 0.5
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: ox + x * s, y: oy + y * s)
            }

            let gold = isDark
                ? Color(red: 212 / 255, green: 166 / 255, blue: 74 / 255)   // #D4A64A
                : Color(red: 184 / 255, green: 137 / 255, blue: 46 / 255)   // #B8892E

            let gridStroke = isDark
                ? Color(red: 138 / 255, green: 133 / 255, blue: 119 / 255).opacity(0.35)
                : Color(red: 142 / 255, green: 139 / 255, blue: 131 / 255).opacity(0.50)

            // 1. Optional Metatron's Cube Sacred Geometry Grid
            if showSacredGrid {
                let lw = max(0.35, 0.55 * s)
                let pts = Self.cubeCenters.map { pt($0.0, $0.1) }
                for c in pts {
                    let r = 18.0 * s
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(gridStroke), lineWidth: lw)
                }
                var mesh = Path()
                for i in 0..<pts.count {
                    for j in (i + 1)..<pts.count {
                        mesh.move(to: pts[i])
                        mesh.addLine(to: pts[j])
                    }
                }
                ctx.stroke(mesh, with: .color(gridStroke), lineWidth: lw * 0.85)
            }

            // 2. Top Gold Resistance Line
            var topBar = Path()
            topBar.move(to: pt(8, 14))
            topBar.addLine(to: pt(192, 14))
            ctx.stroke(topBar, with: .color(gold), lineWidth: max(1.0, 2.0 * s))

            // 3. Geometric 'M' Polygons with vertical gradient
            let gradTop = isDark
                ? Color(red: 242 / 255, green: 237 / 255, blue: 227 / 255)  // #F2EDE3
                : Color(red: 42 / 255, green: 42 / 255, blue: 40 / 255)     // #2A2A28
            let gradBot = isDark
                ? Color(red: 138 / 255, green: 133 / 255, blue: 119 / 255)  // #8A8577
                : Color(red: 168 / 255, green: 165 / 255, blue: 156 / 255)  // #A8A59C

            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [gradTop, gradBot]),
                startPoint: pt(100, 8),
                endPoint: pt(100, 192)
            )

            let polys: [[(CGFloat, CGFloat)]] = [
                [(70, 8), (72.6, 17), (40, 192), (31, 192)],
                [(70, 8), (67.6, 16), (100, 160), (103, 148)],
                [(130, 8), (132.4, 16), (100, 160), (97, 148)],
                [(130, 8), (127.4, 17), (160, 192), (169, 192)]
            ]
            for poly in polys {
                var p = Path()
                p.move(to: pt(poly[0].0, poly[0].1))
                for v in poly.dropFirst() { p.addLine(to: pt(v.0, v.1)) }
                p.closeSubpath()
                ctx.fill(p, with: shading)
            }

            // 4. Gold Bullseye Center Target
            let center = pt(100, 66)
            let outerR = 13.0 * s
            let innerR = 4.5 * s
            ctx.stroke(
                Path(ellipseIn: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2)),
                with: .color(gold),
                lineWidth: max(1.1, 2.6 * s)
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2)),
                with: .color(gold)
            )
        }
    }
}
