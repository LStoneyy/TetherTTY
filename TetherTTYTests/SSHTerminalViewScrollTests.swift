import XCTest
import UIKit
import SwiftTerm
@testable import TetherTTY

/// Regression tests for the touchscreen-scroll fix:
/// direct-touch admission plus the pure scroll→arrow/wheel translation seams.
@MainActor
final class SSHTerminalViewScrollTests: XCTestCase {

    // MARK: - Direct-touch admission policy (pure)

    func testDirectTouchRejectedInNormalBuffer() {
        XCTAssertFalse(SSHTerminalView.shouldAdmitDirectTouch(isAlternateBuffer: false))
    }

    func testDirectTouchAdmittedInAlternateBuffer() {
        XCTAssertTrue(SSHTerminalView.shouldAdmitDirectTouch(isAlternateBuffer: true))
    }

    // MARK: - Velocity classification (pure)

    func testVerticalVelocityAdmitsPan() {
        XCTAssertTrue(SSHTerminalView.isVerticalScrollVelocity(CGPoint(x: 0, y: 100)))
        XCTAssertTrue(SSHTerminalView.isVerticalScrollVelocity(CGPoint(x: -30, y: -200)))
        XCTAssertTrue(SSHTerminalView.isVerticalScrollVelocity(CGPoint(x: 10, y: -500)))
    }

    func testHorizontalVelocityRejectsPan() {
        XCTAssertFalse(SSHTerminalView.isVerticalScrollVelocity(CGPoint(x: 100, y: 0)))
        XCTAssertFalse(SSHTerminalView.isVerticalScrollVelocity(CGPoint(x: -200, y: 40)))
    }

    func testTieVelocityIsAdmittedAsVertical() {
        XCTAssertTrue(SSHTerminalView.isVerticalScrollVelocity(CGPoint(x: 1, y: 1)))
        XCTAssertTrue(SSHTerminalView.isVerticalScrollVelocity(CGPoint(x: -500, y: -500)))
    }

    func testZeroVelocityRejectsPan() {
        XCTAssertFalse(SSHTerminalView.isVerticalScrollVelocity(.zero))
    }

    // MARK: - Begin gate (recognizer wiring)

    func testIndirectScrollDoesNotBeginAtRest() {
        let view = SSHTerminalView(frame: .zero)
        XCTAssertFalse(view.gestureRecognizerShouldBegin(view.indirectScrollGesture),
                       "an unwielded pan has zero velocity, so it must fail rather than swallow taps")
    }

    func testBeginGateLeavesUnrelatedRecognizersAlone() {
        let view = SSHTerminalView(frame: .zero)
        let unrelated = UITapGestureRecognizer()
        XCTAssertTrue(view.gestureRecognizerShouldBegin(unrelated))
    }

    // MARK: - Scroll magnitude cap (pure)

    func testCappedScrollMagnitudeCapsAtForty() {
        XCTAssertEqual(SSHTerminalView.cappedScrollMagnitude(500), 40)
        XCTAssertEqual(SSHTerminalView.cappedScrollMagnitude(-500), 40)
        XCTAssertEqual(SSHTerminalView.cappedScrollMagnitude(40), 40)
        XCTAssertEqual(SSHTerminalView.cappedScrollMagnitude(-40), 40)
    }

    func testCappedScrollMagnitudeHandlesSmallAndExtremeDeltas() {
        XCTAssertEqual(SSHTerminalView.cappedScrollMagnitude(1), 1)
        XCTAssertEqual(SSHTerminalView.cappedScrollMagnitude(-1), 1)
        XCTAssertEqual(SSHTerminalView.cappedScrollMagnitude(0), 0)
        XCTAssertEqual(SSHTerminalView.cappedScrollMagnitude(Int.min), 40)
    }

    // MARK: - Cell location (pure)

    func testCellLocationComputesZeroBasedCell() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        let first = SSHTerminalView.cellLocation(for: CGPoint(x: 10, y: 20), in: bounds, cols: 80, rows: 25)
        XCTAssertEqual(first?.x, 2)
        XCTAssertEqual(first?.y, 0)

        let second = SSHTerminalView.cellLocation(for: CGPoint(x: 200, y: 600), in: bounds, cols: 80, rows: 25)
        XCTAssertEqual(second?.x, 50)
        XCTAssertEqual(second?.y, 23)
    }

    func testCellLocationClampsToVisibleGrid() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        let clampedLow = SSHTerminalView.cellLocation(for: CGPoint(x: -50, y: -50), in: bounds, cols: 80, rows: 25)
        XCTAssertEqual(clampedLow?.x, 0)
        XCTAssertEqual(clampedLow?.y, 0)

        let clampedHigh = SSHTerminalView.cellLocation(for: CGPoint(x: 9_999, y: 9_999), in: bounds, cols: 80, rows: 25)
        XCTAssertEqual(clampedHigh?.x, 79)
        XCTAssertEqual(clampedHigh?.y, 24)
    }

    func testCellLocationGuardsInvalidDimensions() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        XCTAssertNil(SSHTerminalView.cellLocation(for: CGPoint.zero, in: bounds, cols: 0, rows: 25))
        XCTAssertNil(SSHTerminalView.cellLocation(for: CGPoint.zero, in: bounds, cols: 80, rows: 0))
        XCTAssertNil(SSHTerminalView.cellLocation(for: CGPoint.zero, in: CGRect.zero, cols: 80, rows: 25))
    }

    // MARK: - Arrow translation (pure)

    func testArrowSequenceUpNormalCursor() {
        XCTAssertEqual(
            SSHTerminalView.arrowKeySequence(lineDelta: 3, applicationCursor: false),
            repeated(EscapeSequences.moveUpNormal, 3)
        )
    }

    func testArrowSequenceDownNormalCursor() {
        XCTAssertEqual(
            SSHTerminalView.arrowKeySequence(lineDelta: -3, applicationCursor: false),
            repeated(EscapeSequences.moveDownNormal, 3)
        )
    }

    func testArrowSequenceUpApplicationCursor() {
        XCTAssertEqual(
            SSHTerminalView.arrowKeySequence(lineDelta: 2, applicationCursor: true),
            repeated(EscapeSequences.moveUpApp, 2)
        )
    }

    func testArrowSequenceDownApplicationCursor() {
        XCTAssertEqual(
            SSHTerminalView.arrowKeySequence(lineDelta: -2, applicationCursor: true),
            repeated(EscapeSequences.moveDownApp, 2)
        )
    }

    func testArrowSequenceSingleDeltaIsSingleSequence() {
        XCTAssertEqual(SSHTerminalView.arrowKeySequence(lineDelta: 1, applicationCursor: false), EscapeSequences.moveUpNormal)
        XCTAssertEqual(SSHTerminalView.arrowKeySequence(lineDelta: -1, applicationCursor: false), EscapeSequences.moveDownNormal)
    }

    func testArrowSequenceCappedAtForty() {
        XCTAssertEqual(
            SSHTerminalView.arrowKeySequence(lineDelta: 500, applicationCursor: false),
            repeated(EscapeSequences.moveUpNormal, 40)
        )
        XCTAssertEqual(
            SSHTerminalView.arrowKeySequence(lineDelta: -500, applicationCursor: true),
            repeated(EscapeSequences.moveDownApp, 40)
        )
        XCTAssertEqual(
            SSHTerminalView.arrowKeySequence(lineDelta: 40, applicationCursor: false),
            repeated(EscapeSequences.moveUpNormal, 40)
        )
    }

    func testArrowSequenceExtremeNegativeDeltaDoesNotOverflow() {
        XCTAssertEqual(
            SSHTerminalView.arrowKeySequence(lineDelta: Int.min, applicationCursor: false),
            repeated(EscapeSequences.moveDownNormal, 40)
        )
    }

    func testArrowSequenceZeroDeltaIsEmpty() {
        XCTAssertEqual(SSHTerminalView.arrowKeySequence(lineDelta: 0, applicationCursor: false), [])
        XCTAssertEqual(SSHTerminalView.arrowKeySequence(lineDelta: 0, applicationCursor: true), [])
    }

    // MARK: - Translation accumulation (pure)

    func testAccumulatorProducesWholeLineDeltas() {
        var accumulator = ScrollTranslationAccumulator()
        XCTAssertEqual(accumulator.consume(translation: 25, cellHeight: 10), 2)
        XCTAssertEqual(accumulator.consume(translation: 15, cellHeight: 10), 2)
        XCTAssertEqual(accumulator.consume(translation: 1, cellHeight: 10), 0)
        XCTAssertEqual(accumulator.consume(translation: 9, cellHeight: 10), 1)
        XCTAssertEqual(accumulator.remainder, 0)
    }

    func testAccumulatorHandlesNegativeTranslations() {
        var accumulator = ScrollTranslationAccumulator()
        XCTAssertEqual(accumulator.consume(translation: -5, cellHeight: 10), 0)
        XCTAssertEqual(accumulator.consume(translation: -15, cellHeight: 10), -2)
        XCTAssertEqual(accumulator.remainder, 0)
    }

    func testAccumulatorSubCellDeltasCarryRemainder() {
        var accumulator = ScrollTranslationAccumulator()
        XCTAssertEqual(accumulator.consume(translation: 3, cellHeight: 10), 0)
        XCTAssertEqual(accumulator.consume(translation: 3, cellHeight: 10), 0)
        XCTAssertEqual(accumulator.consume(translation: 4, cellHeight: 10), 1)
        XCTAssertEqual(accumulator.remainder, 0)
    }

    func testAccumulatorResetClearsRemainder() {
        var accumulator = ScrollTranslationAccumulator()
        _ = accumulator.consume(translation: 9, cellHeight: 10)
        XCTAssertEqual(accumulator.remainder, 9)
        accumulator.reset()
        XCTAssertEqual(accumulator.remainder, 0)
        XCTAssertEqual(accumulator.consume(translation: 9, cellHeight: 10), 0)
    }

    // MARK: - Wheel translation (live terminal)

    private func makeWheelView(_ escapeBytes: String) -> (SSHTerminalView, () -> [UInt8]) {
        let view = SSHTerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        var sent: [UInt8] = []
        view.onSend = { sent.append(contentsOf: $0) }
        view.feedOutput(Array(escapeBytes.utf8))
        return (view, { sent })
    }

    func testWheelEventSendsSGRUpBytes() {
        let (view, sent) = makeWheelView("\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1006h")
        view.sendScrollAsMouseWheel(lineDelta: 2, location: CGPoint(x: 0, y: 0))
        XCTAssertEqual(sent(), repeated(Array("\u{1B}[<64;1;1M".utf8), 2))
    }

    func testWheelEventSendsSGRDownBytes() {
        let (view, sent) = makeWheelView("\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1006h")
        view.sendScrollAsMouseWheel(lineDelta: -2, location: CGPoint(x: 0, y: 0))
        XCTAssertEqual(sent(), repeated(Array("\u{1B}[<65;1;1M".utf8), 2))
    }

    func testWheelEventRepeatsByCappedMagnitude() {
        let (view, sent) = makeWheelView("\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1006h")
        view.sendScrollAsMouseWheel(lineDelta: 500, location: CGPoint(x: 0, y: 0))
        XCTAssertEqual(sent(), repeated(Array("\u{1B}[<64;1;1M".utf8), 40))
    }

    func testWheelEventIntMinDoesNotOverflow() {
        let (view, sent) = makeWheelView("\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1006h")
        view.sendScrollAsMouseWheel(lineDelta: Int.min, location: CGPoint(x: 0, y: 0))
        XCTAssertEqual(sent(), repeated(Array("\u{1B}[<65;1;1M".utf8), 40))
    }

    func testWheelEventZeroDeltaIsNoOp() {
        let (view, sent) = makeWheelView("\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1006h")
        view.sendScrollAsMouseWheel(lineDelta: 0, location: CGPoint(x: 0, y: 0))
        XCTAssertEqual(sent(), [])
    }

    func testWheelEventClampsLocationToLastCell() {
        let (view, sent) = makeWheelView("\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1006h")
        let cols = view.getTerminal().cols
        let rows = view.getTerminal().rows
        view.sendScrollAsMouseWheel(lineDelta: 1, location: CGPoint(x: 100_000, y: 100_000))
        XCTAssertEqual(sent(), Array("\u{1B}[<64;\(cols);\(rows)M".utf8))
    }

    func testWheelEventSendsX10Bytes() {
        let (view, sent) = makeWheelView("\u{1B}[?1049h\u{1B}[?1000h")
        view.sendScrollAsMouseWheel(lineDelta: 1, location: CGPoint(x: 0, y: 0))
        // x10: ESC [ M, then buttonFlags+32 (64+32), 32+x+1, 32+y+1.
        XCTAssertEqual(sent(), [0x1B, 0x5B, 0x4D, 0x60, 0x21, 0x21])
    }

    // MARK: - Recognizer wiring

    func testIndirectScrollGestureIsWiredToDelegateAndScrollOnly() {
        let view = SSHTerminalView(frame: .zero)
        let gesture = view.indirectScrollGesture

        XCTAssertNotNil(gesture.delegate)
        XCTAssertTrue(gesture.delegate === view)
        XCTAssertEqual(gesture.allowedScrollTypesMask, .all)
        XCTAssertNotEqual(gesture.maximumNumberOfTouches, 0,
                          "maximumNumberOfTouches must not be clamped to zero or direct-touch scrolling breaks")
        XCTAssertTrue(view.gestureRecognizers?.contains(gesture) == true)
    }

    // MARK: - Simultaneous recognition gate

    func testSimultaneousWithNativePanOnlyInAlternateBuffer() {
        let view = SSHTerminalView(frame: .zero)
        let nativePan = view.panGestureRecognizer

        XCTAssertFalse(view.getTerminal().isCurrentBufferAlternate)
        XCTAssertFalse(view.gestureRecognizer(view.indirectScrollGesture, shouldRecognizeSimultaneouslyWith: nativePan))
        XCTAssertFalse(view.gestureRecognizer(nativePan, shouldRecognizeSimultaneouslyWith: view.indirectScrollGesture))

        view.feedOutput(Array("\u{1B}[?1049h".utf8))   // activate alternate screen buffer
        XCTAssertTrue(view.getTerminal().isCurrentBufferAlternate)
        XCTAssertTrue(view.gestureRecognizer(view.indirectScrollGesture, shouldRecognizeSimultaneouslyWith: nativePan))
        XCTAssertTrue(view.gestureRecognizer(nativePan, shouldRecognizeSimultaneouslyWith: view.indirectScrollGesture))
    }

    func testSimultaneousWithUnrelatedRecognizerIsRejected() {
        let view = SSHTerminalView(frame: .zero)
        let unrelated = UITapGestureRecognizer()

        XCTAssertFalse(view.gestureRecognizer(view.indirectScrollGesture, shouldRecognizeSimultaneouslyWith: unrelated))
        XCTAssertFalse(view.gestureRecognizer(unrelated, shouldRecognizeSimultaneouslyWith: view.indirectScrollGesture))
        XCTAssertFalse(view.gestureRecognizer(view.panGestureRecognizer, shouldRecognizeSimultaneouslyWith: unrelated))
        XCTAssertFalse(view.gestureRecognizer(unrelated, shouldRecognizeSimultaneouslyWith: view.panGestureRecognizer))
    }

    // MARK: - Selection clearing on scroll start

    func testScrollStartClearsActiveSelection() {
        let view = SSHTerminalView(frame: .zero)
        view.feedOutput(Array("line one\nline two\nline three\n".utf8))

        view.setSelectionRange(start: Position(col: 0, row: 0), end: Position(col: 7, row: 0))
        XCTAssertTrue(view.hasActiveSelection, "precondition: setSelectionRange should activate a real SwiftTerm selection")

        view.clearSelectionForScrollStart()
        XCTAssertFalse(view.hasActiveSelection, "a real scroll start must clear the active selection so the swipe scrolls instead of extending text selection")
    }

    func testScrollStartWithNoSelectionIsNoOp() {
        let view = SSHTerminalView(frame: .zero)
        XCTAssertFalse(view.hasActiveSelection)

        view.clearSelectionForScrollStart()
        XCTAssertFalse(view.hasActiveSelection)
    }

    // MARK: - Extra pans yield to indirect scroll (alternate buffer, mouse off)

    func testSelectionPanYieldsToIndirectScrollInAlternateBuffer() {
        let view = SSHTerminalView(frame: .zero)
        view.feedOutput(Array("\u{1B}[?1049h".utf8))   // activate alternate screen buffer
        view.selectAll(nil)                            // SwiftTerm installs its selection pan

        XCTAssertTrue(view.hasActiveSelection)

        let wired = SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: false)
        XCTAssertEqual(wired.count, 1, "exactly the SwiftTerm selection pan should be wired")
        XCTAssertTrue(view.gestureRecognizers?.contains(wired[0]) == true)
        XCTAssertFalse(wired[0] === view.panGestureRecognizer)
        XCTAssertFalse(wired[0] === view.indirectScrollGesture)
    }

    func testSelectionPansDoNotYieldInNormalBuffer() {
        let view = SSHTerminalView(frame: .zero)
        view.selectAll(nil)

        XCTAssertTrue(view.hasActiveSelection)
        XCTAssertFalse(view.getTerminal().isCurrentBufferAlternate)
        XCTAssertEqual(SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: false), [],
                       "normal-buffer selection drags must stay fully interactive")
    }

    func testSelectionPansDoNotYieldWithoutActiveSelection() {
        let view = SSHTerminalView(frame: .zero)
        view.feedOutput(Array("\u{1B}[?1049h".utf8))

        XCTAssertTrue(view.getTerminal().isCurrentBufferAlternate)
        XCTAssertFalse(view.hasActiveSelection)
        XCTAssertEqual(SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: false), [])
    }

    func testSelectionPansDoNotYieldWhenMouseReportingActive() {
        let view = SSHTerminalView(frame: .zero)
        view.feedOutput(Array("\u{1B}[?1049h\u{1B}[?1000h".utf8))
        view.selectAll(nil)

        XCTAssertTrue(view.getTerminal().isCurrentBufferAlternate)
        XCTAssertNotEqual(view.getTerminal().mouseMode, .off)
        XCTAssertTrue(view.hasActiveSelection)
        XCTAssertEqual(SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: false), [],
                       "mouse reporting owns alternate-buffer touches, not the mouse-off selection arbitration")
    }

    func testSelectionPanYieldExcludesNativePanAndNonPanRecognizers() {
        let view = SSHTerminalView(frame: .zero)
        let unrelated = UITapGestureRecognizer()
        view.addGestureRecognizer(unrelated)
        view.feedOutput(Array("\u{1B}[?1049h".utf8))
        view.selectAll(nil)

        let wired = SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: false)
        XCTAssertEqual(wired.count, 1)
        XCTAssertFalse(wired[0] === view.panGestureRecognizer)
        XCTAssertFalse(wired[0] === view.indirectScrollGesture)
        XCTAssertFalse(wired[0] === unrelated)
    }

    // MARK: - Extra pans yield to indirect scroll (alternate buffer, mouse active)

    func testMouseDragPanYieldsToIndirectScrollWhenMouseActive() {
        let view = SSHTerminalView(frame: .zero)
        view.feedOutput(Array("\u{1B}[?1049h\u{1B}[?1000h".utf8))

        XCTAssertTrue(view.getTerminal().isCurrentBufferAlternate)
        XCTAssertNotEqual(view.getTerminal().mouseMode, .off)

        let wired = SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: true)
        XCTAssertEqual(wired.count, 1, "mouse-active arbitration wires the SwiftTerm mouse-drag pan")
        XCTAssertTrue(view.gestureRecognizers?.contains(wired[0]) == true)
        XCTAssertFalse(wired[0] === view.panGestureRecognizer)
        XCTAssertFalse(wired[0] === view.indirectScrollGesture)
    }

    func testMouseDragPanDoesNotYieldInNormalBuffer() {
        let view = SSHTerminalView(frame: .zero)
        view.feedOutput(Array("\u{1B}[?1000h".utf8))

        XCTAssertNotEqual(view.getTerminal().mouseMode, .off)
        XCTAssertFalse(view.getTerminal().isCurrentBufferAlternate)
        XCTAssertEqual(SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: true), [])
    }

    func testMouseDragPanDoesNotYieldWhenMouseInactive() {
        let view = SSHTerminalView(frame: .zero)
        view.feedOutput(Array("\u{1B}[?1049h".utf8))

        XCTAssertTrue(view.getTerminal().isCurrentBufferAlternate)
        XCTAssertEqual(view.getTerminal().mouseMode, .off)
        XCTAssertEqual(SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: true), [])
    }

    func testMouseDragArbitrationWiresSelectionPanToo() {
        let view = SSHTerminalView(frame: .zero)
        view.feedOutput(Array("\u{1B}[?1049h\u{1B}[?1000h".utf8))
        view.selectAll(nil)

        let wired = SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: true)
        XCTAssertEqual(wired.count, 2, "mouse-active arbitration wires the mouse-drag pan and any selection pan")
        XCTAssertFalse(wired.contains { $0 === view.panGestureRecognizer || $0 === view.indirectScrollGesture })
    }

    func testMouseDragArbitrationExcludesUnrelatedRecognizers() {
        let view = SSHTerminalView(frame: .zero)
        let unrelated = UITapGestureRecognizer()
        view.addGestureRecognizer(unrelated)
        view.feedOutput(Array("\u{1B}[?1049h\u{1B}[?1000h".utf8))

        let wired = SSHTerminalView.makeExtraPansWaitForIndirectScroll(in: view, requireMouseActive: true)
        XCTAssertEqual(wired.count, 1)
        XCTAssertFalse(wired[0] === unrelated)
    }

    private func repeated(_ sequence: [UInt8], _ count: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(sequence.count * count)
        for _ in 0..<count {
            bytes.append(contentsOf: sequence)
        }
        return bytes
    }
}
