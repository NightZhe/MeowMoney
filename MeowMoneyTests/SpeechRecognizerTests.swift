import XCTest
@testable import MeowMoney

/// `SpeechRecognizer` 依賴麥克風／語音辨識硬體，模擬器上 `recognizer.isAvailable`
/// 恆為 false（zh-TW 語音辨識在模擬器不可用），所以 `.listening` 這條路徑無法在
/// 這裡實跑。這裡只測試不碰硬體的純狀態決策邏輯：`SpeechRecognizer.finishState(for:)`
/// 與 `State` 本身的 Equatable 語意。
final class SpeechRecognizerTests: XCTestCase {

    // MARK: - 靜音逾時 → 新 state

    /// 對應「靜音 watcher 逾時而結束」：不管是使用者從沒開口，還是被判定太吵，
    /// 最終逐字稿都是空的 → 應該進入 `.timeout`，且呼叫端不該再呼叫 onFinish。
    func testFinishStateIsTimeoutWhenTranscriptIsEmpty() {
        XCTAssertEqual(SpeechRecognizer.finishState(for: ""), .timeout)
    }

    /// 逐字稿只有空白字元（沒有辨識到任何實質內容）也要視同空——用的是同一套
    /// trimming 規則，不能因為裡面有個空白字元就誤判成「有內容」。
    func testFinishStateIsTimeoutWhenTranscriptIsWhitespaceOnly() {
        XCTAssertEqual(SpeechRecognizer.finishState(for: "   \n"), .timeout)
    }

    // MARK: - 使用者主動停止（有內容）→ 不是新 state

    /// 對應「使用者主動按停止」且已經講了內容：這是正常結束，維持 `.idle`，
    /// 不能被誤判成逾時——否則使用者講完話按停止，反而看到「沒聽到聲音」。
    func testFinishStateIsIdleWhenTranscriptHasContent() {
        XCTAssertEqual(SpeechRecognizer.finishState(for: "午餐便當一百二"), .idle)
    }

    /// 前後有多餘空白包住的正常內容，trim 後應該還是判定為「有內容」。
    func testFinishStateIsIdleWhenTranscriptHasContentWithSurroundingWhitespace() {
        XCTAssertEqual(SpeechRecognizer.finishState(for: "  早餐 60  "), .idle)
    }

    // MARK: - 失敗（權限／辨識器不可用）→ 仍是 .failed，不會被新 case 蓋過

    /// `.failed` 與新加入的 `.timeout` 是語意完全不同的兩件事（一個是硬體/權限
    /// 錯誤，一個是「這次沒聽到內容但可以直接重試」），Equatable 上必須互斥，
    /// 且都不算「正在聽」。
    func testFailedStateIsDistinctFromTimeoutAndIsNotListening() {
        let failed = SpeechRecognizer.State.failed("目前無法使用中文語音辨識，請確認裝置語言與網路後再試。")
        XCTAssertNotEqual(failed, .timeout)
        XCTAssertFalse(failed.isListening)
    }

    /// `.denied` 同理，不該被新 case 影響。
    func testDeniedStateIsDistinctFromTimeoutAndIsNotListening() {
        let denied = SpeechRecognizer.State.denied("需要「語音辨識」權限才能聽你說話。")
        XCTAssertNotEqual(denied, .timeout)
        XCTAssertFalse(denied.isListening)
    }

    /// `.timeout` 本身也不算「正在聽」——結束了才會進入這個狀態。
    func testTimeoutStateIsNotListening() {
        XCTAssertFalse(SpeechRecognizer.State.timeout.isListening)
    }
}
