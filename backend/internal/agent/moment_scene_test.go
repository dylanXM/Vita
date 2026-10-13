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

func TestDecodeMomentSceneKeepsSituationAndValidatesFocus(t *testing.T) {
	scene, err := decodeMomentSceneState(`{"reply":"听你说完，我把杯子放回桌上。","situation":"两人仍在窗边聊天，TA 把杯子放下。","focus":"table","actions":[]}`)
	if err != nil || scene.Focus != "table" || scene.Situation != "两人仍在窗边聊天，TA 把杯子放下。" {
		t.Fatalf("lost scene: %+v %v", scene, err)
	}
	scene, err = decodeMomentSceneState(`{"reply":"继续聊聊吧。","focus":"invalid"}`)
	if err != nil || scene.Focus != "ambient" {
		t.Fatalf("invalid focus accepted: %+v %v", scene, err)
	}
}

func TestSceneProposalMustContainACompleteKeepsake(t *testing.T) {
	scene, err := decodeMomentSceneState(`{"reply":"我们试试这个方案？","goal":"一起选一杯饮品","challenge":"原来的饮品售罄了","proposal":{"title":"窗边的名字","challenge":"原来的饮品售罄了","decision":"一起选热可可","note":"我喜欢你替这一刻取的名字。"}}`)
	if err != nil || scene.Proposal == nil || scene.Proposal.Decision != "一起选热可可" {
		t.Fatalf("lost joint proposal: %+v %v", scene, err)
	}
	scene, err = decodeMomentSceneState(`{"reply":"再商量一下。","proposal":{"title":"缺失决定"}}`)
	if err != nil || scene.Proposal != nil {
		t.Fatalf("accepted incomplete proposal: %+v %v", scene, err)
	}
}
