import Foundation
import UIKit

class ScreenLocker {

    public static let shared = ScreenLocker()
    private var countdownInterval: TimeInterval?
    // Indicates whether or not the user is currently locked out of the app.
    private var isScreenLockLocked: Bool = false

    // App is inactive or in background
    var appIsInactiveOrBackground: Bool = false {
        didSet {
            // Setter for property indicating that the app is either
            // inactive or in the background, e.g. not "foreground and active."
            if appIsInactiveOrBackground {
                startCountdown()
            } else {
                activateBasedOnCountdown()
                countdownInterval = nil
            }
            ensureUI()
        }
    }

    // App is in background
    var appIsInBackground: Bool = false {
        didSet {
            if appIsInBackground {
                startCountdown()
            } else {
                activateBasedOnCountdown()
            }
            ensureUI()
        }
    }

    private var activeToken: NSObjectProtocol?
    private var resignToken: NSObjectProtocol?
    private var enterForegroundToken: NSObjectProtocol?
    private var enterBackgroundToken: NSObjectProtocol?

    func startObserving() {
        // Initialize the screen lock state.
        clear()
        appIsInactiveOrBackground = UIApplication.shared.applicationState != UIApplication.State.active

        activeToken = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: applicationDidBecomeActive)
        resignToken = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: applicationWillResignActive)
        enterForegroundToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: applicationWillEnterForeground)
        enterBackgroundToken = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: applicationDidEnterBackground)
    }

    func stopObserving() {
        hideLockWindow()
        if let token = activeToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = resignToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = enterForegroundToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = enterBackgroundToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func clear() {
        countdownInterval = nil
        isScreenLockLocked = false
        hideLockWindow()
    }

    func startCountdown() {
        if self.countdownInterval == nil {
            self.countdownInterval = CACurrentMediaTime()
        }
    }

    func activateBasedOnCountdown() {
        if self.isScreenLockLocked {
            // Screen lock is already activated.
            return
        }
        if self.countdownInterval == nil {
            // We became inactive, but never started a countdown.
            return
        }

        let countdown: TimeInterval = CACurrentMediaTime() - countdownInterval!
        let settings = getGAService().getSettings()
        let altimeout = settings != nil ? settings!.altimeout * 60 : 5 * 60
        if Int(countdown) >= altimeout {
            // after timeout
            self.isScreenLockLocked = true
        }
    }

    deinit {
        stopObserving()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        self.appIsInactiveOrBackground = false
    }

    func applicationWillResignActive(_ notification: Notification) {
        self.appIsInactiveOrBackground = true
    }

    func applicationWillEnterForeground(_ notification: Notification) {
        self.appIsInBackground = false
    }

    func applicationDidEnterBackground(_ notification: Notification) {
        self.appIsInBackground = true
    }

    func showLockWindow() {
        // Hide Root Window
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.window!.isHidden = true
        ScreenLockWindow.shared.show()
    }

    func hideLockWindow() {
        ScreenLockWindow.shared.hide()
        // Show Root Window
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.window!.isHidden = false
        // By calling makeKeyAndVisible we ensure the rootViewController becomes first responder.
        // In the normal case, that means the ViewController will call `becomeFirstResponder`
        // on the vc on top of its navigation stack.
        appDelegate.window!.makeKeyAndVisible()
    }

    func ensureUI() {
        if self.isScreenLockLocked {
            if self.appIsInactiveOrBackground {
                showLockWindow()
            } else {
                unlock()
            }
        } else if !self.appIsInactiveOrBackground {
            // App is inactive or background.
            hideLockWindow()
        } else {
            showLockWindow()
        }
    }

    func unlock() {
        if self.appIsInactiveOrBackground {
            return
        }
        clear()
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "autolock"), object: nil, userInfo: nil)
    }
}
