import QtQuick
import "../theme"

NumberAnimation {
    enum Type { StandardSmall, Standard, StandardLarge, StandardExtraLarge, EmphasizedSmall, Emphasized, EmphasizedLarge, EmphasizedExtraLarge, FastSpatial, DefaultSpatial, SlowSpatial, FastEffects, DefaultEffects, SlowEffects }
    property int type: Anim.DefaultSpatial
    duration: type === Anim.SlowSpatial || type === Anim.SlowEffects ? CortetsuDesign.motionDeliberateMs
        : type === Anim.FastSpatial || type === Anim.FastEffects ? CortetsuDesign.motionFastMs
        : CortetsuDesign.motionStandardMs
    easing.type: Easing.BezierSpline
    easing.bezierCurve: type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge
        ? CortetsuDesign.easeInOut : CortetsuDesign.easeOut
}
