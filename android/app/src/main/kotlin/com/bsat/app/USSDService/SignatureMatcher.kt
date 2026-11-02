package com.bsat.app

/**
 * Compares a live USSD screen with the step recorded in an offer's signature
 * and decides what to send. Options are compared by their text, never by
 * position, because Safaricom reorders packages. Anything that is not an exact
 * match stops the session, so a wrong package is never bought.
 */
object SignatureMatcher {
    const val MAX_PAGES_PER_STEP = 5

    data class MenuOption(val input: String, val label: String)

    /** One screen of the recorded conversation and the input chosen on it. */
    class RecordedStep(val screen: String, val choice: String) {
        private val menu = parseMenu(screen)
        val isMenu = menu.size >= 2

        /** Null when the choice is free input, such as the customer number. */
        val label: String? = menu.firstOrNull { it.input == choice }?.label
    }

    sealed class Decision {
        /** Send [input]; [stepsSkipped] recorded steps are no longer needed. */
        data class Send(val input: String, val stepsSkipped: Int = 0) : Decision()

        /** The option is not on this page: send [input] and stay on the step. */
        data class NextPage(val input: String) : Decision()

        data class Stop(val reason: String) : Decision()
    }

    private val optionLine = Regex("^(\\d{1,3}|[*#])\\s*(?:[:)\\-]\\s*|\\.(?!\\d)\\s*|\\s+)(\\S.*)$")

    // A line can hold several options: "00:HOME 98:MORE", or a whole flattened menu.
    private val flattenedOptionStart = Regex("(?<=\\s)(?=(?:\\d{1,3}|[*#])(?::|\\)|\\.(?!\\d)))")
    private val maskedNumber = Regex("\\d{2,}[x*]+\\d{2,}", RegexOption.IGNORE_CASE)
    private val fullNumber = Regex("\\d{9,}")
    private val notIdentifying = Regex("[^a-z0-9.#+=@]")
    private val nextPageLabel = Regex("^(next|more)(page|options?)?$")

    fun parseMenu(screen: String): List<MenuOption> {
        val lines = screen.lines().flatMap { it.split(flattenedOptionStart) }
        return lines.mapNotNull { line ->
            optionLine.find(line.trim())?.let { MenuOption(it.groupValues[1], it.groupValues[2].trim()) }
        }
    }

    /**
     * Option text reduced to what identifies it: spacing and punctuation are
     * ignored, and a customer number shown in the text matches any number.
     * Digits stay exact, so "Sh20" never matches "Sh200".
     */
    fun normalize(label: String): String =
        label.lowercase()
            .replace(maskedNumber, "#")
            .replace(notIdentifying, "")
            .replace(fullNumber, "#")
            .trimEnd('.')

    fun decide(
        screen: String,
        plannedInput: String,
        procedure: List<RecordedStep>,
        stepIndex: Int,
        autoSwitch: Boolean,
        pagesTaken: Int = 0
    ): Decision {
        val expected = procedure.getOrNull(stepIndex) ?: return Decision.Send(plannedInput)
        if (expected.screen.isBlank()) return Decision.Send(plannedInput)

        val options = parseMenu(screen)
        val label = expected.label

        if (label == null) {
            return if ((options.size >= 2) == expected.isMenu) {
                Decision.Send(plannedInput)
            } else {
                Decision.Stop(changedMessage(stepIndex, "the same kind of screen as recorded", screen))
            }
        }

        val wanted = normalize(label)

        // A recorded "Next" may no longer be needed if the package moved up.
        if (autoSwitch && isNextPage(label)) {
            val following = procedure.getOrNull(stepIndex + 1)?.label
            if (following != null) {
                val found = options.filter { normalize(it.label) == normalize(following) }
                if (found.size == 1) return Decision.Send(found[0].input, stepsSkipped = 1)
            }
        }

        val planned = options.firstOrNull { it.input == plannedInput }
        if (planned != null && normalize(planned.label) == wanted) return Decision.Send(plannedInput)
        if (!autoSwitch) return Decision.Stop(changedMessage(stepIndex, label, screen))

        val matches = options.filter { normalize(it.label) == wanted }
        if (matches.size == 1) return Decision.Send(matches[0].input)
        if (matches.size > 1) return Decision.Stop(changedMessage(stepIndex, label, screen))

        val nextPage = options.lastOrNull { isNextPage(it.label) }
        if (nextPage != null && pagesTaken < MAX_PAGES_PER_STEP) return Decision.NextPage(nextPage.input)

        return Decision.Stop(changedMessage(stepIndex, label, screen))
    }

    // The whole label, so packages like "PATAMORE" or "More Data" are never paged through.
    private fun isNextPage(label: String): Boolean = nextPageLabel.matches(normalize(label))

    private fun changedMessage(stepIndex: Int, expected: String, screen: String): String =
        "Offer might have changed at step ${stepIndex + 1}. Expected: $expected. Found: ${screen.trim()}"
}
