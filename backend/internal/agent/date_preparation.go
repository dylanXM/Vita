package agent

// Preparation is an intention for this date, not an accomplished memory.
func datePreparationInstruction(choice string) string {
	switch choice {
	case "talk":
		return "The user wants to talk about their day. Open with one gentle invitation grounded in their recent words; do not ask again what they want to talk about."
	case "quiet":
		return "The user wants quiet company. Keep the opening short and soothing, with no question. Avoid repeated questions and tasks later; follow their pace if they start talking."
	case "story", "surprise":
		return "The user wants to hear your story. Open with one small specific detail grounded in your recorded life, profile or interests; do not invent a past event. Do not ask the user to choose a topic first."
	default:
		return "No preparation preference was selected. Let the user set the pace."
	}
}
