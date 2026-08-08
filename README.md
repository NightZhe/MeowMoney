# 喵喵記帳 MeowMoney 隱私政策

**生效日期：2026 年 8 月 8 日**

喵喵記帳（MeowMoney，以下稱「本 App」）是一款 iOS 語音記帳應用程式。
本頁說明本 App 如何處理你的資料。**簡短版：本 App 沒有伺服器，你的帳目只存在你自己的手機裡。**

---

## 一、本 App 蒐集哪些資料

**不蒐集任何資料。**

本 App 沒有後端伺服器，不需要註冊帳號，也沒有整合任何廣告或分析追蹤服務。
開發者無法看到、取得或還原你的任何使用資料。

## 二、帳目資料的儲存方式

1. 你建立的每一筆帳目（金額、分類、備註、日期）都**儲存在你裝置本機的資料庫**中，
   **開發者無法存取，也不會上傳到任何伺服器**。
2. 這些資料只會隨著 iOS 系統的裝置備份機制（iCloud 備份或電腦備份）一併備份，
   該備份由 Apple 與你自己控管，開發者無法讀取。
3. 你可以在 App 內刪除任何一筆帳目；刪除 App 即會一併移除全部本機資料。

## 三、麥克風與語音辨識

1. 本 App 會請求**麥克風**與**語音辨識**權限。
   **這兩項權限的用途，僅用於把你說的話轉換成文字，以便建立帳目**，不作任何其他用途。
2. 本 App 不會錄製、保存或傳送音訊檔案。語音只在辨識當下即時處理。
3. **語音辨識在裝置不支援離線辨識時，會由 Apple 的語音辨識服務處理，
   此時語音資料會傳送給 Apple。** 這是 iOS 系統內建語音辨識（Speech framework）的運作方式；
   該情況下 Apple 對這些資料的處理，適用 Apple 的隱私政策：
   <https://www.apple.com/legal/privacy/>
4. 本 App 會優先使用裝置端（離線）辨識；只有在你的裝置或語言不支援離線辨識時，
   才會退回使用 Apple 的伺服器辨識。
5. 你可以拒絕這兩項權限。拒絕後語音記帳功能無法使用，但你仍然可以用打字方式記帳，
   帳本與統計功能完全不受影響。

## 四、第三方服務

本 App **未整合任何第三方 SDK**，包含但不限於廣告、分析、當機回報、社群登入服務。
唯一涉及的外部服務是上述第三點所說的 Apple 內建語音辨識。

## 五、兒童隱私

本 App 不會蒐集任何個人資料，因此也不會蒐集兒童的個人資料。

## 六、你的權利

由於開發者不持有你的任何資料，因此沒有可供查詢、更正或匯出的個人資料。
你對資料擁有完全控制權：在 App 內刪除帳目，或刪除 App 以清除全部資料。

## 七、政策變更

本政策如有修改，會更新本頁內容與頁首的生效日期。

## 八、聯絡方式

對本政策有任何疑問，請至本專案的 GitHub Issues 提出：
<https://github.com/NightZhe/MeowMoney/issues>

---

# Privacy Policy (English)

**Effective date: August 8, 2026**

MeowMoney is an iOS voice-driven expense tracking app. **Short version: the app has no server,
and your records never leave your device.**

## 1. Data collection

**None.** MeowMoney has no backend, requires no account, and integrates no advertising or
analytics SDKs. The developer cannot see, retrieve, or reconstruct any of your data.

## 2. How your records are stored

Every entry you create (amount, category, note, date) is stored **in a local database on your
device**. The developer has no access to it, and it is never uploaded to any server. The data is
included in your iOS device backup (iCloud or computer), which is controlled by you and Apple and
cannot be read by the developer. Deleting the app removes all local data.

## 3. Microphone and speech recognition

MeowMoney requests **microphone** and **speech recognition** permissions. These are used **solely
to convert your speech into text so an expense entry can be created**, and for no other purpose.
No audio files are recorded, stored, or transmitted by the app.

**When your device does not support on-device speech recognition, recognition is performed by
Apple's speech recognition service, and your voice data is sent to Apple.** This is how the
built-in iOS Speech framework works; Apple's handling of that data is governed by Apple's privacy
policy at <https://www.apple.com/legal/privacy/>. MeowMoney prefers on-device recognition and only
falls back to Apple's servers when on-device recognition is unavailable for your device or language.

You may decline both permissions. Voice entry will then be unavailable, but you can still add
entries by typing, and the ledger and statistics features are unaffected.

## 4. Third-party services

MeowMoney integrates **no third-party SDKs** of any kind. The only external service involved is
Apple's built-in speech recognition described above.

## 5. Children's privacy

MeowMoney collects no personal data, and therefore collects no personal data from children.

## 6. Your rights

Because the developer holds none of your data, there is nothing to request, correct, or export.
You have full control: delete entries in the app, or delete the app to erase everything.

## 7. Changes to this policy

Changes will be published on this page along with an updated effective date.

## 8. Contact

Questions about this policy can be raised via GitHub Issues:
<https://github.com/NightZhe/MeowMoney/issues>

---

*App 的開發說明文件見 [DEVELOPMENT.md](DEVELOPMENT.md)。*
