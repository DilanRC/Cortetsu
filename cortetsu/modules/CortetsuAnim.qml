import QtQuick
import "../theme"

// Shared number animation. Entries and popovers use easeOut; Emphasized*
// types move the interface itself and use easeInOut. Durations come from
// CortetsuDesign, so Reduced motion reaches every consumer.
NumberAnimation {
    enum Type { StandardSmall, Standard, StandardLarge, StandardExtraLarge,
        EmphasizedSmall, Emphasized, EmphasizedLarge, EmphasizedExtraLarge,
        FastSpatial, DefaultSpatial, SlowSpatial, FastEffects, DefaultEffects, SlowEffects }
    property int type: CortetsuAnim.DefaultSpatial
    duration: type === CortetsuAnim.FastEffects ? CortetsuDesign.motionInstantMs
        : type === CortetsuAnim.DefaultEffects || type === CortetsuAnim.FastSpatial
            || type === CortetsuAnim.StandardSmall || type === CortetsuAnim.EmphasizedSmall ? CortetsuDesign.motionFastMs
        : type === CortetsuAnim.SlowEffects || type === CortetsuAnim.DefaultSpatial
            || type === CortetsuAnim.Standard || type === CortetsuAnim.Emphasized ? CortetsuDesign.motionStandardMs
        : type === CortetsuAnim.StandardExtraLarge || type === CortetsuAnim.EmphasizedExtraLarge ? CortetsuDesign.motionPanelMs
        : CortetsuDesign.motionDeliberateMs
    easing.type: Easing.BezierSpline
    easing.bezierCurve: type >= CortetsuAnim.EmphasizedSmall && type <= CortetsuAnim.EmphasizedExtraLarge
        ? CortetsuDesign.easeInOut : CortetsuDesign.easeOut
}
