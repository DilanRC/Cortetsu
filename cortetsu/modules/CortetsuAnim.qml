import QtQuick
import "CortetsuDesign.js" as CortetsuDesign

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
    easing.type: Easing.OutCubic
}
