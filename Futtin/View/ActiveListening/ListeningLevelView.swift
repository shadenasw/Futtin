import SwiftUI
import AVFoundation

struct ListeningLevelView: View {
    let scenario: Scenario
    var onComplete: (() -> Void)? = nil
    @Binding var showTabBar: Bool

    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var progressVM: ProgressViewModel
    @State private var isPlaying = false
    @State private var showChoices = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioTimer: Timer?
    @State private var userInterrupted = false
    @State private var userHasChosen = false

    @State private var feedbackText: String? = nil
    @State private var audioClosed = false

    @State private var activeBanner: BannerType? = nil
    @State private var bannerPlayer: AVAudioPlayer?
    @State private var timeoutWorkItem: DispatchWorkItem?


    var body: some View {
        ZStack {
         Color("Background").ignoresSafeArea()
                .navigationBarBackButtonHidden(true)
            VStack(spacing: 30) {
                HStack {
                    Button(action: {
                        stopAudio()
                        presentationMode.wrappedValue.dismiss()
                        
                    }) {
                        Image(systemName: "chevron.backward")
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .bold))
                    }
                    Spacer()
                }
                .padding(.horizontal)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("المستوى \(arabicLevelName(for: scenario.level))")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.white)

                    Text(scenario.title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
                .padding(.top, -30)

                Spacer()
                    .frame(height: 80)

                Button(action: {
                    toggleAudio()
                }) {
                    Image(audioClosed ? "closed" : (isPlaying ? "Open 1" : "replay"))
                        .resizable()
                        .frame(width: 180, height: 180)
                        .padding()
                }

                if showChoices {
                    Text("ما هو أفضل رد تتوقعه في هذا الموقف؟")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }

                if showChoices {
                    VStack(spacing: 15) {
                        ForEach(scenario.branches.indices, id: \.self) { index in
                            let item = scenario.branches[index]
                            Button(action: {
                                guard !userHasChosen else { return }
                                userHasChosen = true
                                feedbackText = item.feedback

                                if let audio = item.narratorAudio {
                                    playBranchAudio(named: audio)
                                }

                                // ✅ توزيع النقاط حسب نوع الفيدباك
                                switch item.feedbackType {
                                case .correct:
                                    progressVM.addPoints(10)
                                case .neutral:
                                    progressVM.addPoints(5)
                                case .incorrect:
                                    progressVM.addPoints(1)
                                }
                            })
 {
                                ZStack {
                                    Image("Option listen")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 60)
                                        .cornerRadius(12)
                                    HStack {
                                        Spacer()
                                        Text(item.userOption)
                                            .foregroundColor(.black)
                                            .font(.system(size: 16, weight: .bold))
                                            .multilineTextAlignment(.trailing)
                                        Spacer(minLength: 50)
                                        Text(optionLetter(for: index))
                                            .foregroundColor(.black)
                                            .font(.system(size: 16, weight: .bold))
                                            .padding(.leading, 8)
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            .disabled(userHasChosen)
                            .padding(.horizontal, 30)
                        } 
                    }
                } else {
                    Button(action: checkUserInterruption) {
                        ZStack {
                            Image("Interrupt")
                                .resizable()
                                .frame(width: 210, height: 45)
                                .cornerRadius(10)
                            Text("مقاطعة")
                                .foregroundColor(.black)
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                    .padding(.top, 28)
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()
            }

            if userHasChosen, let feedback = feedbackText {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    ZStack(alignment: .topTrailing) {
                        Image("popup")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 300)

                        VStack(spacing: 15) {
                            Spacer().frame(height: 40)
                            Text(notificationTitle())
                                .font(.title2)
                                .bold()
                                .foregroundColor(.black)

                            Text(feedback)
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            Spacer(minLength: 20)
                        }
                        .frame(width: 300, height: 300)
                        .clipped()

                      
                        Button(action: {
                            // ✅ استدعِ onComplete بعد ما المستخدم يضغط X
                            withAnimation {
                                feedbackText = nil
                                userHasChosen = false
                            }
                            onComplete?() // ✅ هنا تنفذ بعد عرض الفيدباك
                            presentationMode.wrappedValue.dismiss()
                        }) {
                        Image(systemName: "xmark")
                                .font(.system(size: 24))
                                .foregroundColor(.black)
                                .padding(10)
                        }
                    }
                }
                .transition(.opacity)
            } 

            VStack {
                if activeBanner != nil {
                    ZStack(alignment: .top) {
                        // 🟦 تغميق خفيف للمحتوى خلف الإشعار فقط
                        Color.black.opacity(0.60)
                            .frame(height: 100) // غطي فقط خلف الإشعار
                            .blur(radius: 3)

                        // 🟨 الإشعار نفسه
                        BannerView(type: activeBanner!)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            
                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: activeBanner)
            .zIndex(2)
        }
        .onAppear {
            playMainAudio()
            showTabBar = false // ❌ يخفي التاب بار
        }
        .onDisappear {
            stopAudio()
            showTabBar = true // ✅ يرجع التاب بار عند الرجوع
        }

    }

    func toggleAudio() {
        if isPlaying {
            stopAudio()
            audioClosed = true  // ✅ غيّر صورة الزر
        } else {
            playMainAudio()
            audioClosed = false
        }
    }


    func playMainAudio() {
        stopAudio() // أوقف كل شيء أول

        playAudio(named: scenario.mainAudio)

        userInterrupted = false
        showChoices = false
        userHasChosen = false
        feedbackText = nil
        activeBanner = nil

        audioTimer?.invalidate()

        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let current = audioPlayer?.currentTime else { return }

            if userInterrupted {
                audioTimer?.invalidate()
            }
        }

        // ✅ ألغِ أي تايم أوت سابق
        timeoutWorkItem?.cancel()

        // ✅ احسب المدة الإجمالية وانتظر بعدها 5 ثواني
        let totalDuration = audioPlayer?.duration ?? 0
        let delayAfterEnd: TimeInterval = 5.0

        let workItem = DispatchWorkItem {
            if !userInterrupted && !showChoices && !userHasChosen {
                triggerTimeout()
            }
        }

        timeoutWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + delayAfterEnd, execute: workItem)
    }


    func playAudio(named name: String) {
        guard let path = Bundle.main.path(forResource: name, ofType: "mp3") else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            audioPlayer?.prepareToPlay()
            audioPlayer?.currentTime = 0 // ✅ مهم جدًا: نبدأ من البداية
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("❌ خطأ في تشغيل الصوت:", error)
        }
    }


    func playBranchAudio(named name: String) {
        stopAudio()
        playAudio(named: name)
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioTimer?.invalidate()
        timeoutWorkItem?.cancel() // ✅ لازم ينلغي دائمًا
        isPlaying = false
    }



    func checkUserInterruption() {
        guard let current = audioPlayer?.currentTime else { return }

        let duration = scenario.interruptionRange.upperBound - scenario.interruptionRange.lowerBound
        let margin: TimeInterval = duration < 3.0 ? 1.5 : 1.0

        let lower = scenario.interruptionRange.lowerBound - margin
        let upper = scenario.interruptionRange.upperBound + margin

        print("⏱️ current time = \(current)")
        print("📍 interruption allowed: \(lower)...\(upper)")

        if current >= lower && current <= upper {
            userInterrupted = true
            playSound(named: "success_ping")
            triggerHapticFeedback()
            showBanner(type: .success)
                stopAudio()
                showChoices = true
            
       

        } else {
            stopAudio()
            playSound(named: "fail_ping")
            showBanner(type: .fail)
            restartAudio(after: 2.5)
        }
    }

      

    func restartAudio(after delay: TimeInterval = 2.0) {
        stopAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            playMainAudio()
        }
    }

    func triggerTimeout() {
        stopAudio()
        playSound(named: "timeout_ping")
        showBanner(type: .timeout)
        restartAudio(after: 2.5)
    }

    func playSound(named name: String) {
        guard let path = Bundle.main.path(forResource: name, ofType: "mp3") else {
            print("❌ الملف غير موجود: \(name).mp3")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.prepareToPlay()
            player.play()
            bannerPlayer = player  // ✅ خزّنه هنا عشان ما يختفي
        } catch {
            print("❌ فشل تشغيل الصوت: \(error)")
        }
    }

    func showBanner(type: BannerType) {
        playSound(named: type.soundName)
        activeBanner = type
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                activeBanner = nil
            }
        }
    }
    func triggerHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func optionLetter(for index: Int) -> String {
        switch index {
        case 0: return "أ"
        case 1: return "ب"
        case 2: return "ج"
        default: return ""
        }
    }
    func notificationTitle() -> String {
        guard let index = scenario.branches.firstIndex(where: { $0.feedback == feedbackText }) else {
            return "إجابة"
        }

        switch scenario.branches[index].feedbackType {
        case .correct: return "أحسنت!"
        case .neutral: return "إجابتك جيدة"
        case .incorrect: return "لا بأس"
        }
    }

    func arabicLevelName(for level: Int) -> String {
        switch level {
        case 1: return "الأول"
        case 2: return "الثاني"
        case 3: return "الثالث"
        case 4: return "الرابع"
        case 5: return "الخامس"
        case 6: return "السادس"
        case 7: return "السابع"
        case 8: return "الثامن"
        case 9: return "التاسع"
        case 10: return "العاشر"
        default: return "\(level)"
        }
    }
}
