import UIKit
import CoreNFC
import ASN1Kit

class ViewController: UIViewController, NFCTagReaderSessionDelegate {

    var myNumberString=""
    var myNumberBytes:ArraySlice<UInt8> = []
    @IBOutlet weak var Pin: UITextField!
    @IBOutlet weak var idImageView: UIImageView!
    @IBOutlet weak var nameImageView: UIImageView!
    @IBOutlet weak var addressImageView: UIImageView!

    @IBOutlet weak var
myNumberLabel:UILabel!
    @IBOutlet weak var
nameLabel:UILabel!
    @IBOutlet weak var
addressLabel:UILabel!
    @IBOutlet weak var
birthdayLabel:UILabel!
    @IBOutlet weak var
sexLabel:UILabel!
    var session: NFCTagReaderSession?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        view.addGestureRecognizer(tap)
    }
    
    @IBAction func beginScanning(_ sender: UIButton) {
        guard NFCTagReaderSession.readingAvailable else {
            let alertController = UIAlertController(
                title: "Scanning Not Supported",
                message: "This device doesn't support tag scanning.",
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true, completion: nil)
            return
        }
        let pincode:String=self.Pin.text!
        if(pincode.count==4){
            self.myNumberLabel.text=""
            self.session = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self)
            self.session?.alertMessage = "iPhoneの上部にマイナンバーカードを載せてください"
            self.session?.begin()
        }
        else{
            self.myNumberLabel.text="PINコードを入力して下さい。"
        }
    }
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print("tagReaderSessionDidBecomeActive(_:)")
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let readerError = error as! NFCReaderError
                print(readerError.code, readerError.localizedDescription)
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print("tagReaderSession(_:didDetect:)")
        
        let tag = tags.first!
        session.connect(to:tag){(error:Error?)in
            if nil != error
            {
                        session.alertMessage = "Unable to connect to tag."
                        session.invalidate()
                        return
            }
            guard case NFCTag.iso7816(let myNumberCard) = tag else {
                session.invalidate(errorMessage: "ISO 7816 準拠ではない")
                return
            }
            session.alertMessage = "マイナバーカードを読み取っています…"
            self.selectDF(tag: myNumberCard)
        }
    }
    func selectDF(tag:NFCISO7816Tag){
        print("# SELECT FILE: 券面入力補助AP (DF)")
        let apdu=NFCISO7816APDU.init(data: Data([0x00,0xA4,0x04,0x0C,0x0A,0xD3, 0x92, 0x10, 0x00, 0x31, 0x00, 0x01, 0x01, 0x04, 0x08]))
        tag.sendCommand(apdu: apdu!) { (responseData, sw1, sw2, error) in
            if let error = error {
                print(error)
                self.session?.invalidate(errorMessage: error.localizedDescription)
                return
            }
            let hx1=String(format:"%02X",sw1)
            let hx2=String(format:"%02X",sw2)
            print(hx1)
            print(hx2)
            if sw1 != 0x90 {
                self.session?.invalidate(errorMessage: "SELECT DFエラー: ステータス \(sw1),\(sw2)")
                return
            }
            self.selectEF(tag:tag)
        }
    }
    
    func selectEF(tag:NFCISO7816Tag){
            print("# SELECT FILE: 券面入力補助用PIN (EF)")
            let apdu=NFCISO7816APDU.init(data: Data([0x00,0xA4,0x02,0x0C,0x02,0x00,0x11]))
            tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
                if let error = error {
                    print(error)
                    self.session?.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                let hx1=String(format:"%02X",sw1)
                let hx2=String(format:"%02X",sw2)
                print(hx1)
                print(hx2)
                if sw1 != 0x90 {
                    self.session?.invalidate(errorMessage: "SELECT EFエラー: ステータス \(sw1),\(sw2)")
                    return
                }
                self.verifyPin(tag:tag)
            })
        }
    func verifyPin(tag:NFCISO7816Tag){
        print("# VERIFY: 券面入力補助用PIN")
            let pincode:String=self.Pin.text!
            let p1=0x30+UInt8(bitPattern:Int8((pincode.character(at: 0)?.wholeNumberValue)!))
            let p2=0x30+UInt8(bitPattern:Int8((pincode.character(at: 1)?.wholeNumberValue)!))
            let p3=0x30+UInt8(bitPattern:Int8((pincode.character(at: 2)?.wholeNumberValue)!))
            let p4=0x30+UInt8(bitPattern:Int8((pincode.character(at: 3)?.wholeNumberValue)!))
            let apdu=NFCISO7816APDU.init(data: Data([0x00,0x20,0x00,0x80,0x04,p1,p2,p3,p4]))
            tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
                if let error = error {
                    print(error)
                    self.session?.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                let hx1=String(format:"%02X",sw1)
                let hx2=String(format:"%02X",sw2)
                print(hx1)
                print(hx2)
                if sw1 != 0x90 {
                    if(sw1==0x63){
                        let tries=String(sw2.toString().character(at: 1)!)
                        self.session?.invalidate(errorMessage: "PINコードが間違っています。残り" + tries + "回")
                    }
                    self.session?.invalidate(errorMessage: "VERIFY PINでエラー: ステータス \(sw1),\(sw2)")
                    return
                }
                
                self.selectMyNumberFile(tag: tag)
            })
    }
    func selectMyNumberFile(tag:NFCISO7816Tag){
        print("# SELECT FILE: マイナンバー (EF)")
            let apdu=NFCISO7816APDU.init(data: Data([0x00,0xA4,0x02,0x0C,0x02,0x00,0x01]))
            tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
                if let error = error {
                    print(error)
                    self.session?.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                let hx1=String(format:"%02X",sw1)
                let hx2=String(format:"%02X",sw2)
                print(hx1)
                print(hx2)
                if sw1 != 0x90 {
                    self.session?.invalidate(errorMessage: "SELECT FILEエラー: ステータス \(sw1),\(sw2)")
                    return
                }
                self.readBinaryMyNumberFile(tag: tag)
            })
    }
    
    func readBinaryMyNumberFile(tag:NFCISO7816Tag){
        print("# READ BINARY: マイナンバー読み取り（4～15バイト目が個人番号）")
        let apdu=NFCISO7816APDU.init(data: Data([0x00,0xB0,0x00,0x00,0x00]))
            tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
                if let error = error {
                    print(error)
                    self.session?.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                let hx1=String(format:"%02X",sw1)
                let hx2=String(format:"%02X",sw2)
                print(hx1)
                print(hx2)
                if sw1 != 0x90 {
                    self.session?.invalidate(errorMessage: "READ BINARYエラー: ステータス \(sw1),\(sw2)")
                    return
                }
                let responseData = [UInt8](responseData)
                let myNumberString=String(bytes:responseData[3...14], encoding: .utf8)!
                self.myNumberBytes=responseData[3...14]
                self.myNumberString=myNumberString
                DispatchQueue.main.sync {
                    self.myNumberLabel.text=myNumberString
                }
                self.selectInfoFile(tag: tag)
            })
    }
    
    func selectInfoFile(tag:NFCISO7816Tag){
        print("# SELECT FILE: 基本4情報 (EF)")
        let apdu=NFCISO7816APDU.init(data: Data([0x00,0xA4,0x02,0x0C,0x02,0x00,0x02]))
            tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
                if let error = error {
                    print(error)
                    self.session?.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                let hx1=String(format:"%02X",sw1)
                let hx2=String(format:"%02X",sw2)
                print(hx1)
                print(hx2)
                if sw1 != 0x90 {
                    self.session?.invalidate(errorMessage: "SELECT FILEエラー: ステータス \(sw1),\(sw2)")
                    return
                }
                self.readInfoFile(tag:tag)
            })
    }
    
    func readInfoFile(tag:NFCISO7816Tag){
        print("# READ BINARY: 基本4情報の読み取り")
        let apdu=NFCISO7816APDU.init(data: Data([0x00,0xB0,0x00,0x00,0xFF]))
        tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
            if let error = error {
                print(error)
                self.session?.invalidate(errorMessage: error.localizedDescription)
                return
            }
            let hx1=String(format:"%02X",sw1)
            let hx2=String(format:"%02X",sw2)
            print(hx1)
            print(hx2)
            if sw1 != 0x90 {
                self.session?.invalidate(errorMessage: "READ BINARYエラー: ステータス \(sw1),\(sw2)")
                return
            }
            var responseBytes = [UInt8](responseData)
            responseBytes=[UInt8](responseData[19...responseData.count-1])
            var dictionary=[String:[UInt8]]()
            var byteSequence:[UInt8]=[]
            
            for b in responseBytes{
                if(b==223){
                    
                }
                else if(b==96){
                    
                }
                else if(b==35){// start of address
                    dictionary.updateValue(byteSequence, forKey: "Name")
                    byteSequence=[]
                }
                else if(b==36){//start of birthday
                    dictionary.updateValue(byteSequence, forKey: "Address")
                    byteSequence=[]
                }
                else if(b==37){ // start of sex
                    dictionary.updateValue(byteSequence, forKey: "Birthday")
                    byteSequence=[]
                }
                else if(b==255)// end of data
                {
                    dictionary.updateValue(byteSequence, forKey: "Sex")
                    break
                }
                else{
                    byteSequence.append(b)
                }
            }
            let name=String(bytes:dictionary["Name"]!,encoding:.utf8)
            let address=String(bytes:dictionary["Address"]!,encoding:.utf8)
            let birthday=String(bytes:dictionary["Birthday"]!,encoding:.utf8)?.replacingOccurrences(of: "\u{8}", with: "")
            var sex=String(bytes:dictionary["Sex"]!,encoding:.utf8)?.replacingOccurrences(of: "\u{1}", with: "")
            
            if(sex=="1"){
                sex="男性"
            }
            else if(sex=="2"){
                sex="女性"
            }
            else{
                sex="その他"
            }
            DispatchQueue.main.sync {
                self.nameLabel.text=name
                self.addressLabel.text=address
                self.birthdayLabel.text=birthday
                self.sexLabel.text=sex
            }
            self.selectVisualDF(tag: tag)
        })
    }
    
    func selectVisualDF(tag:NFCISO7816Tag){
            print("# SELECT VISUAL FILE: 券面入力補助AP (DF)")
        let apdu=NFCISO7816APDU.init(data: Data([0x00,0xA4,0x04,0x0C,0x0A,0xD3, 0x92, 0x10, 0x00, 0x31, 0x00, 0x01, 0x01, 0x04, 0x02]))
            tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
                if let error = error {
                    print(error)
                    self.session?.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                let hx1=String(format:"%02X",sw1)
                let hx2=String(format:"%02X",sw2)
                print(hx1)
                print(hx2)
                if sw1 != 0x90 {
                    self.session?.invalidate(errorMessage: "SELECT VISUAL DFエラー: ステータス \(sw1),\(sw2)")
                    return
                }
                self.selectVisualEF(tag:tag)
        })
    }
    
    func selectVisualEF(tag:NFCISO7816Tag){
        print("# SELECT VISUAL FILE: 券面入力補助用PIN (EF)")
        let apdu=NFCISO7816APDU.init(data: Data([0x00,0xA4,0x02,0x0C,0x02,0x00,0x13]))
        tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
            if let error = error {
                print(error)
                self.session?.invalidate(errorMessage: error.localizedDescription)
                return
            }
            let hx1=String(format:"%02X",sw1)
            let hx2=String(format:"%02X",sw2)
            print(hx1)
            print(hx2)
            if sw1 != 0x90 {
                self.session?.invalidate(errorMessage: "SELECT VISUAL FILEエラー: ステータス \(sw1),\(sw2)")
                return
            }
            self.verifyVisualPin(tag:tag)
        })
    }
    
    func verifyVisualPin(tag:NFCISO7816Tag){
        print("# VERIFY VISUAL PIN: 券面入力補助用PIN")

        if(self.myNumberString != "") {
            let p1=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 0)?.wholeNumberValue)!))
            let p2=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 1)?.wholeNumberValue)!))
            let p3=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 2)?.wholeNumberValue)!))
            let p4=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 3)?.wholeNumberValue)!))
            let p5=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 4)?.wholeNumberValue)!))
            let p6=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 5)?.wholeNumberValue)!))
            let p7=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 6)?.wholeNumberValue)!))
            let p8=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 7)?.wholeNumberValue)!))
            let p9=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 8)?.wholeNumberValue)!))
            let p10=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 9)?.wholeNumberValue)!))
            let p11=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 10)?.wholeNumberValue)!))
            let p12=0x30+UInt8(bitPattern:Int8((self.myNumberString.character(at: 11)?.wholeNumberValue)!))
            let apdu=NFCISO7816APDU.init(data: Data([0x00,0x20,0x00,0x80,0x0C,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12]))
            tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
                if let error = error {
                    print(error)
                    self.session?.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                let hx1=String(format:"%02X",sw1)
                let hx2=String(format:"%02X",sw2)
                print(hx1)
                print(hx2)
                if sw1 != 0x90 {
                    self.session?.invalidate(errorMessage: "READ VISUAL FILEエラー: ステータス \(sw1),\(sw2)")
                    return
                }
                self.selectVisualFileBinary(tag: tag)
            })
        }
    }
    
    func selectVisualFileBinary(tag:NFCISO7816Tag){
        print("# SELECT VISUAL FILE BINARY")
        let apdu=NFCISO7816APDU.init(data: Data([0x00,0xA4,0x02,0x0C,0x02,0x00,0x02]))
        tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
            if let error = error {
                print(error)
                self.session?.invalidate(errorMessage: error.localizedDescription)
                return
            }
            let hx1=String(format:"%02X",sw1)
            let hx2=String(format:"%02X",sw2)
            print(hx1)
            print(hx2)
            if sw1 != 0x90 {
                self.session?.invalidate(errorMessage: "READ VISUAL FILEエラー: ステータス \(sw1),\(sw2)")
                return
            }
            self.readVisualFilesBinary(tag: tag)
        })
    }
    
    func recursiveCall(stopLoop:Bool,tag:NFCISO7816Tag,i:Int, byteSequence:Data,handler:@escaping(Data)throws ->Void){
        var counter=i
        var bytes=byteSequence
        let apdu=NFCISO7816APDU.init(data: Data([0x00,0xB0,UInt8(i),0x00,0x00]))
        tag.sendCommand(apdu: apdu!, completionHandler:{ (responseData, sw1, sw2, error) in
            if let error = error {
                print(error)
                self.session?.invalidate(errorMessage: error.localizedDescription)
                return
            }
            let hx1=String(format:"%02X",sw1)
            let hx2=String(format:"%02X",sw2)
            print(hx1)
            print(hx2)
            if sw1 != 0x90 {
                self.session?.invalidate(errorMessage: "READ VISUAL FILEエラー: ステータス \(sw1),\(sw2)")
                return
            }
            let responseBytes=[UInt8](responseData)
            counter+=1
            if(responseBytes[responseBytes.count-1]==255){ // End of data break loop
                bytes.append(responseData)
                //bytes.append(contentsOf: responseBytes)
                //return bytes
                do{
                    try handler(bytes)
                }catch{
                    print(error)
                }
            }
            else{
                bytes.append(contentsOf: responseBytes)
                self.recursiveCall(stopLoop: stopLoop, tag: tag, i: counter, byteSequence: bytes){
                    result in
                    do{
                        try handler(result)
                    }catch{
                        print(error)
                    }
                }
            }
        })
    }
    
    func readVisualFilesBinary(tag:NFCISO7816Tag){
        var fileRead=false
        var i = 0
        
        print("# READ VISUAL FILE BINARY")
        //let apdu=NFCISO7816APDU.init(data: Data([0x00,0xB0,UInt8(i),0x00,0x00]))
        let apdu=NFCISO7816APDU.init(data: Data([0x00,0xB0,0x01,0x00,0x00]))
        // do while loop until all file has been read
        var byteSequence:Data=Data.init()
        self.recursiveCall(stopLoop: false, tag: tag, i: 0, byteSequence: byteSequence){
            result in
            byteSequence=result
            do{
                let res=try ASN1Decoder.decode(asn1: byteSequence)
                res.data.items?.forEach({ item in
                    let itemTagNo=item.tagNo!
                    let itemData=item.data.primitive!
                    if(itemTagNo == 37)// 37 Name
                    {
                        let nameImage=UIImage(data:itemData)
                        DispatchQueue.main.sync {
                            self.nameImageView.image=nameImage
                        }
                    }
                    else if(itemTagNo == 38)// 38 Addr
                    {
                        let addrImage=UIImage(data:itemData)
                        DispatchQueue.main.sync {
                            self.addressImageView.image=addrImage
                        }
                    }
                    else if(itemTagNo == 39)// 39 Photo
                    {
                        let photoImage=UIImage(data:itemData)
                        DispatchQueue.main.sync {
                            self.idImageView.image=photoImage
                        }
                    }
                })
                self.session?.alertMessage = "読み取り完了！"
                self.session?.invalidate()
            }catch{
                print(error)
            }
        }
        
        
    }
}

extension String {
 
    func index(at position: Int, from start: Index? = nil) -> Index? {
        let startingIndex = start ?? startIndex
        return index(startingIndex, offsetBy: position, limitedBy: endIndex)
    }
 
    func character(at position: Int) -> Character? {
        guard position >= 0, let indexPosition = index(at: position) else {
            return nil
        }
        return self[indexPosition]
    }
}

extension UInt8 {
    func toString() -> String {
        var str = String(self, radix: 16).uppercased()
        if str.count == 1 {
            str = "0" + str
        }
        return str
    }
    
    func toHexString() -> String {
        var str = self.toString()
        str = "0x\(str)"
        return str
    }
}
