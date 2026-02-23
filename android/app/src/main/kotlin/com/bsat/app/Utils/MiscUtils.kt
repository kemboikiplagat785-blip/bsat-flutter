package com.bsat.app.Utils

class MiscUtils {
    fun extractOptionText(response: String, optionIndex: String): String? {
        // 1. Split the response into individual lines
        val lines = response.lines()

        val delimiters = listOf(" ", ":", ".", ")")
        val regex = "[ ${Regex.escape(":. )")}]".toRegex()

        for (line in lines) {
            val trimmedLine = line.trim()

            // 2. Check if this line starts with the option index we are looking for
            // We check for "1 ", "1:", "1.", "1)" to be flexible with different USSD formats
            if (trimmedLine.startsWith("$optionIndex ") ||
                trimmedLine.startsWith("$optionIndex:") ||
                trimmedLine.startsWith("$optionIndex.") ||
                trimmedLine.startsWith("$optionIndex)")
            ) {
                // 3. Extract everything AFTER the index and separator
                return trimmedLine.substringAfter(optionIndex)
                            .split(regex, limit = 2)
                            .last()
                            .trim()
            }
        }

        return null // Return null if the option was not found
    }
    fun findOptionIndex(response: String, optionText: String): String? {
        // 1. Split the response into individual lines
        val lines = response.lines()

        for (line in lines) {
            val trimmedLine = line.trim()

            // 2. Check if this line contains the option text we are looking for
            // ignoreCase = true makes it search for "bonga" or "Bonga" equally
            if (trimmedLine.contains(optionText, ignoreCase = true)) {
                
                // 3. Find the separator (usually ':', '.', or ')')
                // Most USSDs use "1:Text", "1. Text" or "1) Text"
                val separators = listOf(":", ".", ")", "-", " ")
                val foundSeparator = separators.firstOrNull { trimmedLine.contains(it) }

                if (foundSeparator != null) {
                    // 4. Extract everything BEFORE the separator
                    val indexPart = trimmedLine.substringBefore(foundSeparator).trim()
                    
                    // Optional: Ensure the index is actually a number or single character
                    // to avoid accidentally returning a sentence if the line is messy
                    if (indexPart.length <= 3) {
                        return indexPart
                    }
                }
            }
        }

        return null // Return null if the option was not found
    }
    
}

