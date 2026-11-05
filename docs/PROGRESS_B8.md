# PROGRESS B8 - the photo check of the framed render

The two tests of `Tests/FrameKitTests/FrameKitRenderTests.swift` that check that
the frame does not change the picture (`testRenderFullHasTheSizeOfTheLayoutAndKeepsThePicture`
and `testFilm120PaintsTheMarginAndKeepsThePicture`) do not draw the source a
second time any more: they crop the photo area of the framed render and compare
it with the render of the same source without a frame (the biggest difference of
the channels must stay at 5 or below). The other tests
(`testRenderWithoutFrameCopiesEveryPixel`, `testLoaderReadsTheSampleAndItsMetadata`)
are not changed.
