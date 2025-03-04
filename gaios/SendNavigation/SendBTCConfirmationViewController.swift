import Foundation
import UIKit
import PromiseKit

class SendBTCConfirmationViewController: KeyboardViewController, SlideButtonDelegate, UITextViewDelegate {

    var wallet: WalletItem?
    var transaction: Transaction!

    @IBOutlet var content: SendBTCConfirmationView!
    private var uiErrorLabel: UIErrorLabel!
    private var isFiat = false
    private var connected = true

    private var updateToken: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        updateToken = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: EventType.Network.rawValue), object: nil, queue: .main, using: updateConnection)

        tabBarController?.tabBar.isHidden = true
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        title = NSLocalizedString("id_send", comment: "")
        content.fromLabel.text = transaction.isSweep ?  NSLocalizedString("id_sweep_from_paper_wallet", comment: "") : wallet?.localizedName()
        content.slidingButton.delegate = self
        content.slidingButton.buttonText = NSLocalizedString("id_slide_to_send", comment: "")
        uiErrorLabel = UIErrorLabel(self.view)
        content.textView.delegate = self
        content.textView.text = NSLocalizedString("id_add_a_note_only_you_can_see_it", comment: "")
        content.textView.textColor = UIColor.customTitaniumLight()
        content.sendingTitle.text = NSLocalizedString("id_sending", comment: "")
        content.fromTitle.text = NSLocalizedString("id_from", comment: "")
        content.toTitle.text = NSLocalizedString("id_to", comment: "")
        content.myNotesTitle.text = NSLocalizedString("id_my_notes", comment: "")
        content.feeTitle.text = NSLocalizedString("id_total_with_fee", comment: "")
        content.assetsTitle.text = NSLocalizedString("id_sending", comment: "")
        content.assetsFeeTitle.text = NSLocalizedString("id_fee", comment: "")
        content.load()

        // setup liquid view
        let isLiquid = getGdkNetwork(getNetwork()).liquid
        content.assetsView.heightAnchor.constraint(equalToConstant: 0).isActive = !isLiquid
        content.sendView.heightAnchor.constraint(equalToConstant: 0).isActive = isLiquid
        content.assetsView.isHidden = !isLiquid
        content.sendView.isHidden = isLiquid
        content.assetsView.layoutIfNeeded()
        content.sendView.layoutIfNeeded()

        // load content
        setupCurrencyButton()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        content.currencyButton.addTarget(self, action: #selector(click(_:)), for: .touchUpInside)
        content.textView.textColor = UIColor.customTitaniumLight()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        content.currencyButton.removeTarget(self, action: #selector(click(_:)), for: .touchUpInside)
    }

    func updateConnection(_ notification: Notification) {
        guard let connected = notification.userInfo?["connected"] as? Bool else { return }
        self.connected = connected
    }

    deinit {
        if let token = updateToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func reload() {
        let addressee = transaction.addressees.first!
        content.toLabel.text = addressee.address
        let isLiquid = getGdkNetwork(getNetwork()).liquid
        if isLiquid {
            let tag = addressee.assetTag ?? "btc"
            let asset = wallet?.balance[tag]?.assetInfo
            content.assetTableCell?.configure(tag: tag, asset: asset, satoshi: addressee.satoshi)
            let (amount, denom) = Balance.convert(details: ["satoshi": transaction.fee])!.get(tag: "btc")
            content.assetsFeeLabel.text = "\(amount) \(denom)"
        } else {
            content.amountText.text = Balance.convert(details: ["satoshi": addressee.satoshi])!.get(tag: isFiat ? "fiat" : "btc").0
            let (amount, denom) = Balance.convert(details: ["satoshi": addressee.satoshi + transaction.fee])!.get(tag: isFiat ? "fiat" : "btc")
            content.feeLabel.text = "\(amount) \(denom)"
        }
    }

    func setupCurrencyButton() {
        guard let settings = getGAService().getSettings() else { return }
        if !isFiat {
            content.currencyButton.setTitle(settings.denomination.string, for: UIControl.State.normal)
            content.currencyButton.backgroundColor = UIColor.customMatrixGreen()
        } else {
            content.currencyButton.setTitle(settings.getCurrency(), for: UIControl.State.normal)
            content.currencyButton.backgroundColor = UIColor.clear
        }
        content.currencyButton.setTitleColor(UIColor.white, for: UIControl.State.normal)
    }

    @objc func click(_ sender: Any?) {
        isFiat = !isFiat
        setupCurrencyButton()
        reload()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == UIColor.customTitaniumLight() {
            textView.text = nil
            textView.textColor = UIColor.white
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = NSLocalizedString("id_add_a_note_only_you_can_see_it", comment: "")
            textView.textColor = UIColor.customTitaniumLight()
        } else {
            transaction.memo = textView.text
        }
    }

    func completed(slidingButton: SlidingButton) {
        let bgq = DispatchQueue.global(qos: .background)

        firstly {
            uiErrorLabel.isHidden = true
            self.startAnimating()
            return Guarantee()
        }.then(on: bgq) {
            signTransaction(transaction: self.transaction)
        }.then(on: bgq) { call in
            call.resolve(self, connected: {
                return self.connected })
        }.map(on: bgq) { resultDict in
            let result = resultDict["result"] as? [String: Any]
            if self.transaction.isSweep {
                let tx = result!["transaction"] as? String
                _ = try getSession().broadcastTransaction(tx_hex: tx!)
                return nil
            } else {
                return try getSession().sendTransaction(details: result!)
            }
        }.then(on: bgq) { (call: TwoFactorCall?) -> Promise<[String: Any]> in
            call?.resolve(self, connected: {
                return self.connected }) ?? Promise<[String: Any]> { seal in seal.fulfill([:]) }
        }.done { _ in
            self.executeOnDone()
        }.catch { error in
            self.stopAnimating()
            self.content.slidingButton.reset()
            self.uiErrorLabel.isHidden = false
            if let twofaError = error as? TwoFactorCallError {
                switch twofaError {
                case .failure(let localizedDescription), .cancel(let localizedDescription):
                    self.uiErrorLabel.text = localizedDescription
                }
            } else {
                self.uiErrorLabel.text = error.localizedDescription
            }
        }
    }

    func executeOnDone() {
        self.startAnimating(message: NSLocalizedString("id_transaction_sent", comment: ""))
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.1) {
            self.stopAnimating()
            getAppDelegate()?.instantiateViewControllerAsRoot(storyboard: "Wallet", identifier: "TabViewController")
        }
    }

    override func keyboardWillShow(notification: Notification) {
        // Modified slightly for use in Green from the public release at "Managing the Keyboard" from Text Programming Guide for iOS
        super.keyboardWillShow(notification: notification)
        if let kbSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            let contentInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: kbSize.height, right: 0.0)
            content.scrollView.contentInset = contentInsets
            content.scrollView.scrollIndicatorInsets = contentInsets
            var aRect = self.view.frame
            aRect.size.height -= kbSize.height
            if !aRect.contains(content.textView.frame.origin) {
                content.scrollView.scrollRectToVisible(aRect, animated: true)
            }
        }
    }

    override func keyboardWillHide(notification: Notification) {
        super.keyboardWillHide(notification: notification)
        let contentInsets = UIEdgeInsets.zero
        content.scrollView.contentInset = contentInsets
        content.scrollView.scrollIndicatorInsets = contentInsets
    }
}

@IBDesignable
class SendBTCConfirmationView: UIView {
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var slidingButton: SlidingButton!
    @IBOutlet weak var feeLabel: UILabel!
    @IBOutlet weak var fromLabel: UILabel!
    @IBOutlet weak var fromView: UIView!
    @IBOutlet weak var toLabel: UILabel!
    @IBOutlet weak var sendingTitle: UILabel!
    @IBOutlet weak var fromTitle: UILabel!
    @IBOutlet weak var toTitle: UILabel!
    @IBOutlet weak var myNotesTitle: UILabel!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var feeTitle: UILabel!
    @IBOutlet weak var amountText: UITextField!
    @IBOutlet weak var currencyButton: UIButton!
    @IBOutlet weak var assetsView: UIView!
    @IBOutlet weak var sendView: UIView!
    @IBOutlet weak var assetsTitle: UILabel!
    @IBOutlet weak var assetsFeeTitle: UILabel!
    @IBOutlet weak var assetsFeeLabel: UILabel!
    @IBOutlet weak var assetsCell: UIView!
    var assetTableCell: AssetTableCell?
    var gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    func load() {
        assetTableCell = Bundle.main.loadNibNamed("AssetTableCell", owner: self, options: nil)!.first as? AssetTableCell
        assetsCell.addSubview(assetTableCell!)
        gradientLayer = fromView.makeGradientCard()
        fromView.layer.insertSublayer(gradientLayer, at: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = fromView.bounds
        gradientLayer.setNeedsLayout()
        assetTableCell?.frame = assetsCell.bounds
        assetTableCell?.setNeedsLayout()
    }
}
