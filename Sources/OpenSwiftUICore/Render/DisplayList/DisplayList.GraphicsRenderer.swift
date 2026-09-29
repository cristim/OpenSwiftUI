//
//  DisplayList.GraphicsRenderer.swift
//  OpenSwiftUICore
//
//  Audited for 6.0.87
//  Status: Blocked by RenderBox and GraphicsContext
//  ID: EFAEDE41CB8C85EF3A6A18DC05438A3C

package import Foundation

extension DisplayList {
    final package class GraphicsRenderer {
        package enum PlatformViewMode {
            case ignored
            case unsupported
            case rendered(update: Bool)
        }
        
        private struct Cache {
            var callbacks: [CallbackKey: Void /* ORBDisplayListContents */]
            var animators: [AnimatorKey: Void /* _DisplayList_AnyEffectAnimator */ ]
            
            struct CallbackKey: Hashable {
                var index: DisplayList.Index.ID
                var seed: DisplayList.Seed
                var scale: CGFloat
            }
            
            struct AnimatorKey: Hashable {
                var index: DisplayList.Index.ID
            }
        }
        
        private var oldCache: DisplayList.GraphicsRenderer.Cache
        private var newCache: DisplayList.GraphicsRenderer.Cache
        var index: DisplayList.Index
        var time: Time
        var nextTime: Time
        var stableIDs: _DisplayList_StableIdentityMap?
        var inTransitionGroup: Bool
        var stateHashes: [StrongHash]
        package var platformViewMode: DisplayList.GraphicsRenderer.PlatformViewMode

        /// Alpha accumulated by the `.opacity` effects currently in scope.
        ///
        /// The factor is carried here rather than pushed onto the Core Graphics
        /// context, because a context alpha is not honoured by every Core Graphics
        /// this draws into: with it set, a fill comes out empty rather than
        /// translucent. Accumulating it and folding it into each paint at draw time
        /// works the same everywhere and treats every paint kind alike.
        private var pendingOpacity: Float = 1
        
        /// Starts a renderer with nothing cached and no transition in progress.
        ///
        /// The cache and the animation state are per-renderer bookkeeping: there is
        /// nothing to carry in from anywhere, so an empty cache and a zero time are
        /// the honest starting values rather than a placeholder for something
        /// unknown.
        package init(platformViewMode: DisplayList.GraphicsRenderer.PlatformViewMode) {
            self.oldCache = .init(callbacks: [:], animators: [:])
            self.newCache = .init(callbacks: [:], animators: [:])
            self.index = .init()
            self.time = .init()
            self.nextTime = .init()
            self.stableIDs = nil
            self.inTransitionGroup = false
            self.stateHashes = []
            self.platformViewMode = platformViewMode
        }
        
        package func render(at time: Time, do body: () -> Void) {
            _openSwiftUIUnimplementedFailure()
        }
        
        package func renderDisplayList(_ list: DisplayList, at time: Time, in ctx: inout GraphicsContext) {
            _openSwiftUIUnimplementedFailure()
        }
        
        /// Draws a whole list, item by item.
        package func render(list: DisplayList, in ctx: inout GraphicsContext) {
            renderAll(of: list, in: &ctx)
        }
        
        /// Draws one display list item.
        ///
        /// The walk mirrors `DisplayListStdoutRenderer`: a content item is drawn
        /// through its own `draw`, an effect carries a nested list, and anything else
        /// has nothing to paint. Content is handed to the paint rather than matched
        /// here, so a new paint needs no change in this file and a gradient reaches
        /// Core Graphics by the same route a solid colour does.
        package func render(item: DisplayList.Item, in ctx: inout GraphicsContext) {
            switch item.value {
            case .content(let content):
                render(content: content, frame: item.frame, in: &ctx)
            case .effect(let effect, let list):
                render(effect: effect, list: list, in: &ctx)
            case .empty, .states:
                break
            }
        }

        private func renderAll(of list: DisplayList, in ctx: inout GraphicsContext) {
            for item in list.items {
                render(item: item, in: &ctx)
            }
        }

        private func render(effect: DisplayList.Effect, list: DisplayList, in ctx: inout GraphicsContext) {
            switch effect {
            case .opacity(let alpha):
                // Nested opacity effects multiply, which is what the documented
                // behaviour of applying opacity to a view whose opacity was already
                // transformed is.
                let previous = pendingOpacity
                pendingOpacity = previous * alpha
                renderAll(of: list, in: &ctx)
                pendingOpacity = previous
            case .transform(.affine(let affine)):
                guard let cgContext = ctx.cgContext else {
                    renderAll(of: list, in: &ctx)
                    return
                }
                CGContextSaveGState(cgContext)
                CGContextConcatCTM(cgContext, affine)
                renderAll(of: list, in: &ctx)
                CGContextRestoreGState(cgContext)
            default:
                renderAll(of: list, in: &ctx)
            }
        }

        private func render(
            content: DisplayList.Content,
            frame: CGRect,
            in ctx: inout GraphicsContext
        ) {
            switch content.value {
            case .color(let color):
                color.multiplyingOpacity(by: pendingOpacity).draw(
                    path: Path(frame),
                    style: .fill(FillStyle()),
                    in: ctx,
                    bounds: frame
                )
            case .shape(let path, let paint, let fillStyle):
                // The display list's shape case carries the FillStyle the caller
                // asked for and the paint takes a PathDrawingStyle, so the caller's
                // fill style is passed through rather than discarded for a default.
                // The same folding as the colour case, applied to whatever paint the
                // caller asked for rather than to one kind of paint in particular.
                paint.multiplyingOpacity(by: pendingOpacity).draw(
                    path: path,
                    style: .fill(fillStyle),
                    in: ctx,
                    bounds: frame
                )
            case .flattened(let list, let offset, _):
                // The offset is baked into the context's transform rather than into
                // each item's frame, so a nested gradient resolves its unit geometry
                // against the same bounds it would have had on screen.
                guard let cgContext = ctx.cgContext else {
                    renderAll(of: list, in: &ctx)
                    return
                }
                CGContextSaveGState(cgContext)
                CGContextTranslateCTM(cgContext, offset.x, offset.y)
                renderAll(of: list, in: &ctx)
                CGContextRestoreGState(cgContext)
            default:
                break
            }
        }
        
        package func drawImplicitLayer(in ctx: inout GraphicsContext, content: (inout GraphicsContext) -> Void) {
            _openSwiftUIUnimplementedFailure()
        }
        
        package func renderPlatformView(_ view: AnyObject?, in ctx: GraphicsContext, size: CGSize, viewType: any Any.Type) {
            _openSwiftUIUnimplementedFailure()
        }
    }
}
