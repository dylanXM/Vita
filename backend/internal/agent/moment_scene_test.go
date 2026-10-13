package agent

import "testing"

func TestDecodeMomentScene(t *testing.T) {
	text, actions, err := decodeMomentScene("```json\n" + `{"reply":"那就靠窗坐一会儿。","actions":[{"label":"聊聊今天","message":"我想听你说说今天的事。"},{"label":"拍张照片","message":"帮我生成一张图片"},{"label":"换个话题","message":"你最近读了什么？"}]}` + "\n```")
	if err != nil || text != "那就靠窗坐一会儿。" || len(actions) != 2 || actions[1].Label != "换个话题" {
		t.Fatalf("reply=%q actions=%v err=%v", text, actions, err)
	}
}

func TestDecodeMomentSceneRejectsBrokenJSON(t *testing.T) {
	for _, raw := range []string{`{"reply":"unfinished`, `{"actions":[]}`, `{"reply":"   "}`} {
		if _, _, err := decodeMomentScene(raw); err == nil {
			t.Fatalf("accepted invalid scene: %s", raw)
		}
	}
}

func TestDecodeMomentSceneSupportsPlainReply(t *testing.T) {
	text, actions, err := decodeMomentScene("先听你说。🙂")
	if err != nil || text != "先听你说。🙂" || len(actions) != 0 {
		t.Fatalf("plain reply changed: %q %v %v", text, actions, err)
	}
}
