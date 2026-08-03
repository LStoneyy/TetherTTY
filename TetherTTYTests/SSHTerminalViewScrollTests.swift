import XCTest
import UIKit
import SwiftTerm
@testable import TetherTTY

/// Regression tests for the touchscreen-scroll fix:
/// direct-touch admission plus the pure scroll→arrow translation seams.
@MainActor
final class SSHTerminalViewScrollTests: XCTestCase {

    // MARK: - Direct-touch admission policy (pure)

    func testDirectTouchRejectedInNormalBuffer() {
        XCTAssertFalse(SSHTerminalView.shouldAdmitDirectTouch(isAlternateBuffer: false, mouseReportingActive: false))
        XCTAssertFalse(SSHTerminalView.shouldAdmitDirectTouch(isAlternateBuffer: false, mouseReportingActive: true))
    }

    func testDirectTouchAdmittedInAlternateBufferWhenMouseInactive() {
        XCTAssertTrue(SSHTerminalView.shouldAdmitDirectTouch(isAlternateBuffer: true, mouseReportingActive: false))
    }

    func testDirectTouchRejectedInAlternateBufferWhenMouseActive() {
        XCTAssertFalse(SSHTerminalView.shouldAdmitDirectTouch(isAlternateBuffer: true, mouseReportingActive: true))
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

    private func repeated(_ sequence: [UInt8], _ count: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(sequence.count * count)
        for _ in 0..<count {
            bytes.append(contentsOf: sequence)
        }
        return bytes
    }
}
