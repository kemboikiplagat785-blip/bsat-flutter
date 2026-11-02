package com.bsat.app

import com.bsat.app.SignatureMatcher.Decision
import com.bsat.app.SignatureMatcher.RecordedStep
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SignatureMatcherTest {
    private val bundles = "Select:\n1:1GB @ Sh20\n2:2GB @ Sh200\n3:Sh20 Calls\n0:Next"
    private val recorded = listOf(RecordedStep(bundles, "1"))

    private fun decide(
        screen: String,
        planned: String = "1",
        procedure: List<RecordedStep> = recorded,
        autoSwitch: Boolean = true,
        pages: Int = 0
    ) = SignatureMatcher.decide(screen, planned, procedure, 0, autoSwitch, pages)

    @Test
    fun parsesEverySeparatorAndFlattenedMenus() {
        assertEquals(listOf("1", "2", "00"), SignatureMatcher.parseMenu("1:Data\n2. Calls\n00 Home").map { it.input })
        assertEquals(listOf("Data", "Calls"), SignatureMatcher.parseMenu("Pick 1:Data 2:Calls").map { it.label })
    }

    @Test
    fun decimalAmountIsNotAnOption() {
        assertTrue(SignatureMatcher.parseMenu("1.5GB bundle").isEmpty())
    }

    @Test
    fun unchangedScreenFollowsThePlannedInput() {
        assertEquals(Decision.Send("1"), decide(bundles))
    }

    @Test
    fun reorderedPackageStopsWithoutAutoSwitch() {
        assertTrue(decide("1:2GB @ Sh200\n2:1GB @ Sh20", autoSwitch = false) is Decision.Stop)
    }

    @Test
    fun reorderedPackageSwitchesToItsNewPositionWithAutoSwitch() {
        assertEquals(Decision.Send("2"), decide("1:2GB @ Sh200\n2:1GB @ Sh20"))
    }

    @Test
    fun similarPriceIsNeverAccepted() {
        assertTrue(decide("1:1GB @ Sh200\n2:Calls") is Decision.Stop)
    }

    @Test
    fun missingPackagePagesThenStops() {
        val screen = "1:Calls\n2:SMS\n98:More"
        assertEquals(Decision.NextPage("98"), decide(screen))
        assertTrue(decide(screen, pages = SignatureMatcher.MAX_PAGES_PER_STEP) is Decision.Stop)
    }

    @Test
    fun duplicatedPackageIsAmbiguousAndStops() {
        assertTrue(decide("1:Calls\n2:1GB @ Sh20\n3:1GB @ Sh20") is Decision.Stop)
    }

    @Test
    fun customerNumberInOptionTextDoesNotCountAsAChange() {
        val procedure = listOf(RecordedStep("1:Buy for 0701135362\n2:Cancel", "1"))
        assertEquals(Decision.Send("1"), decide("1:Buy for 0722000111\n2:Cancel", procedure = procedure))
        assertEquals(Decision.Send("1"), decide("1:Buy for 0722***111\n2:Cancel", procedure = procedure))
    }

    @Test
    fun numberPromptStopsIfItBecomesAMenu() {
        val procedure = listOf(RecordedStep("Enter the number", "n"))
        assertEquals(Decision.Send("0722000111"), decide("Enter the number", "0722000111", procedure))
        assertTrue(decide("1:Data\n2:Calls", "0722000111", procedure) is Decision.Stop)
    }

    @Test
    fun homeStepIsMatchedByItsText() {
        val procedure = listOf(RecordedStep("Number saved\n0:Back\n00:Home", "00"))
        assertEquals(Decision.Send("00"), decide("Number saved\n0:Back\n00:Home", "00", procedure))
        assertEquals(Decision.Send("9"), decide("Number saved\n0:Back\n9:Home", "00", procedure))
    }

    @Test
    fun recordedNextIsSkippedWhenThePackageMovedUp() {
        val procedure = listOf(
            RecordedStep("1:Calls\n0:Next", "0"),
            RecordedStep("1:1GB @ Sh20\n2:SMS", "1")
        )
        assertEquals(Decision.Send("2", stepsSkipped = 1), decide("1:Calls\n2:1GB @ Sh20\n0:Next", "0", procedure))
    }

    @Test
    fun noSignatureOrUnrecordedStepFollowsThePlannedInput() {
        assertEquals(Decision.Send("7"), decide("anything", "7", emptyList()))
        assertEquals(Decision.Send("7"), decide("anything", "7", listOf(RecordedStep("", "7"))))
    }

    // Screens captured from *544# on a real phone.
    private val mainMenu = "0:90GB+1200Min@3000\n1:PATAMORE\n2:Deals\n3:Daily\n4:Weekly\n5:Monthly\n" +
        "6:MakeBundle\n7:Okoa\n8:NoExpiry\n9:FunZone\n10:SocialBundle\n11:Data+\n12:GIFT\n13:Mins\n98:MORE"
    private val monthly = "0:Sh1000=8GB+400MINS+100SMS\n1:All In One\n2:Data Plans\n3:HOT Deals\n" +
        "4:Chagua Bei Yako\n5:5G Plans\n6:Join Emerald\n7:GO Monthly Plus\n8:Buy For Other\n9:Minutes Plans\n00:HOME 98:MORE"
    private val afterNumber = "1:Data Only Plans\n2:All In One\n0:BACK 00:HOME"

    @Test
    fun parsesTwoOptionsSharingALine() {
        assertEquals(
            listOf("1", "2", "0", "00"),
            SignatureMatcher.parseMenu(afterNumber).map { it.input }
        )
        assertEquals(
            SignatureMatcher.MenuOption("98", "MORE"),
            SignatureMatcher.parseMenu(monthly).last()
        )
    }

    @Test
    fun homeAndMoreSharingALineAreMatchedByTheirOwnText() {
        val procedure = listOf(RecordedStep(afterNumber, "00"))
        assertEquals("HOME", procedure[0].label)
        assertEquals(Decision.Send("00"), decide(afterNumber, "00", procedure))
        assertEquals(
            Decision.Send("9"),
            decide("1:Data Only Plans\n0:BACK 9:HOME", "00", procedure)
        )
    }

    @Test
    fun pagingUsesMoreNeverHome() {
        val procedure = listOf(RecordedStep("1:Other\n8:Unlimited Plan\n00:HOME 98:MORE", "8"))
        assertEquals(Decision.NextPage("98"), decide(monthly, "8", procedure))
    }

    @Test
    fun packagesContainingMoreAreNotPagedThrough() {
        val procedure = listOf(RecordedStep("1:Other\n2:Unlimited Plan", "2"))
        assertTrue(decide("1:PATAMORE\n2:More Data\n0:BACK 00:HOME", "2", procedure) is Decision.Stop)
    }

    @Test
    fun movedPackageOnTheRealMenuSwitchesByText() {
        val procedure = listOf(RecordedStep(mainMenu, "5"))
        val shuffled = mainMenu.replace("5:Monthly", "5:Weekly").replace("4:Weekly", "4:Monthly")
        assertEquals(Decision.Send("5"), decide(mainMenu, "5", procedure))
        assertEquals(Decision.Send("4"), decide(shuffled, "5", procedure))
        assertTrue(decide(shuffled, "5", procedure, autoSwitch = false) is Decision.Stop)
    }

    @Test
    fun changedPromoIsAChange() {
        val procedure = listOf(RecordedStep(mainMenu, "0"))
        val newPromo = mainMenu.replace("0:90GB+1200Min@3000", "0:90GB+1200Min@2000")
        assertTrue(decide(newPromo, "0", procedure, autoSwitch = false) is Decision.Stop)
        assertEquals(Decision.NextPage("98"), decide(newPromo, "0", procedure))
    }

    @Test
    fun normalizeKeepsDigitsExact() {
        assertFalse(SignatureMatcher.normalize("Sh10=1GB") == SignatureMatcher.normalize("Sh101GB"))
        assertFalse(SignatureMatcher.normalize("Sh20") == SignatureMatcher.normalize("Sh200"))
        assertEquals(SignatureMatcher.normalize("1GB@Sh20."), SignatureMatcher.normalize("1 GB @ sh20"))
    }
}
