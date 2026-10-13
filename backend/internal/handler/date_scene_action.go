package handler

func validDateSceneAction(location, action string) bool {
	switch location {
	case "cinema":
		return action == "romance" || action == "mystery" || action == "pause"
	case "cafe":
		return action == "coffee" || action == "tea" || action == "toast"
	case "restaurant":
		return action == "dinner" || action == "dessert" || action == "toast"
	case "ballroom":
		return action == "dance" || action == "slow_dance" || action == "terrace"
	default:
		return false
	}
}
