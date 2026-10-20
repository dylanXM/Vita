package agent

import "strings"

// Catch explicit media-generation requests before a chat model can promise
// delivery. The system policy covers other phrasing; chat has no media tools.
func requestsPaidMedia(text string) bool {
	text = strings.ToLower(text)
	media := false
	for _, word := range []string{"照片", "图片", "圖", "图像", "拍照", "自拍", "语音", "語音", "录音", "錄音", "视频", "視頻", "音频", "音訊", "影片", "photo", "picture", "image", "audio", "voice", "video", "speech", "foto", "imagen", "vídeo", "voz", "imagem", "áudio", "写真", "画像", "音声", "動画", "사진", "이미지", "음성", "영상", "صورة", "صوت", "فيديو"} {
		if strings.Contains(text, word) {
			media = true
			break
		}
	}
	if !media {
		return false
	}
	for _, word := range []string{"生成", "拍", "发", "發", "给我", "給我", "帮我", "幫我", "画", "畫", "想看", "想听", "想聽", "来张", "來張", "来段", "來段", "send", "make", "create", "generate", "record", "show me", "draw", "please", "envía", "envia", "genera", "quiero", "crie", "envie", "quero", "作って", "送って", "見せて", "찍", "만들", "보내", "أرسل", "ارسل", "أنشئ", "اصنع"} {
		if strings.Contains(text, word) {
			return true
		}
	}
	return false
}

func paidMediaChatRefusal(locale string) string {
	switch locale {
	case "zh-Hans":
		return "这里不能直接生成图片、语音或视频。请到「共同体验」选择项目并确认花费金币，再告诉我你的具体需求。"
	case "zh-Hant":
		return "這裡不能直接生成圖片、語音或影片。請到「共同體驗」選擇項目並確認花費金幣，再告訴我你的具體需求。"
	case "es":
		return "No puedo generar imágenes, audio ni vídeos en este chat. Ve a Experiencias compartidas y confirma el coste en monedas para las opciones disponibles."
	case "pt":
		return "Não posso gerar imagens, áudio ou vídeos neste chat. Vá a Experiências compartilhadas e confirme o custo em moedas das opções disponíveis."
	case "ja":
		return "このチャットでは画像・音声・動画を生成できません。「共同体験」で利用できる項目を選び、コインの使用を確認してから希望を入力してください。"
	case "ko":
		return "이 채팅에서는 이미지, 음성, 영상을 생성할 수 없어요. 공동 체험에서 가능한 항목을 선택하고 코인 사용을 확인한 뒤 원하는 내용을 알려 주세요."
	case "ar":
		return "لا يمكنني إنشاء صور أو صوت أو فيديو في هذه الدردشة. انتقل إلى التجارب المشتركة واختر تجربة متاحة وأكّد تكلفتها بالعملات وحدد طلبك."
	default:
		return "I can't generate images, audio or videos in this chat. Open Shared Experiences, choose an available experience, and confirm the coin cost and your preferences there."
	}
}
