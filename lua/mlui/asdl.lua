local pvm = require("pvm")

local M = {}

function M.Define(T)
    T:Define [[
        module Core {
            Id = NoId
               | IdValue(string value) unique
        }

        module Style {
            Space = S0 | S0_5 | S1 | S1_5 | S2 | S2_5 | S3 | S3_5
                  | S4 | S5 | S6 | S7 | S8 | S9 | S10 | S11 | S12
                  | S14 | S16 | S20 | S24 | S28 | S32 | S36 | S40
                  | S44 | S48 | S52 | S56 | S60 | S64 | S72 | S80
                  | S96 | SPx

            Fraction = F1_2 | F1_3 | F2_3
                     | F1_4 | F2_4 | F3_4
                     | F1_5 | F2_5 | F3_5 | F4_5
                     | F1_6 | F2_6 | F3_6 | F4_6 | F5_6
                     | FFull

            ColorScale = Slate | Gray | Zinc | Neutral | Stone
                       | Red | Orange | Amber | Yellow | Lime | Green
                       | Emerald | Teal | Cyan | Sky | Blue | Indigo
                       | Violet | Purple | Fuchsia | Pink | Rose
                       | White | Black | Transparent

            Shade = S50 | S100 | S200 | S300 | S400
                  | S500 | S600 | S700 | S800 | S900 | S950

            ColorRef = Palette(Style.ColorScale scale, Style.Shade shade) unique
                     | WhiteRef
                     | BlackRef
                     | TransparentRef

            Radius = R0 | RSm | RBase | RMd | RLg | RXl | R2xl | R3xl | RFull
            BorderW = BW0 | BW1 | BW2 | BW4 | BW8

            Opacity = O0 | O5 | O10 | O20 | O25 | O30 | O40 | O50
                    | O60 | O70 | O75 | O80 | O90 | O95 | O100

            FontSize = TxtXs | TxtSm | TxtBase | TxtLg | TxtXl
                     | Txt2xl | Txt3xl | Txt4xl | Txt5xl | Txt6xl

            FontWeight = Thin | ExtraLight | Light | Normal | Medium
                       | Semibold | Bold | ExtraBold | WeightBlack

            TextAlign = TLeft | TCenter | TRight | TJustify

            Leading = LeadingNone | LeadingTight | LeadingSnug
                    | LeadingNormal | LeadingRelaxed | LeadingLoose

            Tracking = TrackingTighter | TrackingTight | TrackingNormal
                     | TrackingWide | TrackingWider | TrackingWidest

            Cursor = CursorDefault | CursorPointer | CursorText
                   | CursorMove | CursorGrab | CursorGrabbing
                   | CursorNotAllowed

            ScrollAxis = ScrollX | ScrollY | ScrollBoth
            Overflow = OverflowVisible | OverflowHidden | OverflowScroll | OverflowAuto

            Display = DisplayFlow | DisplayFlex | DisplayGrid
            Axis = AxisRow | AxisCol
            Wrap = WrapOff | WrapOn

            Justify = JustifyStart | JustifyCenter | JustifyEnd
                    | JustifyBetween | JustifyAround | JustifyEvenly

            Items = ItemsStart | ItemsCenter | ItemsEnd | ItemsStretch | ItemsBaseline
            Self = SelfAuto | SelfStart | SelfCenter | SelfEnd | SelfStretch | SelfBaseline

            Length = LAuto
                   | LHug
                   | LFill
                   | LFixed(number px) unique
                   | LFrac(Style.Fraction value) unique

            Basis = BAuto
                  | BHug
                  | BFixed(number px) unique
                  | BFrac(Style.Fraction value) unique

            Track = TAuto
                  | TFr(number fr) unique
                  | TFixed(number px) unique
                  | TMinMax(number min_px, number max_px) unique

            BpCond = AnyBp | SmUp | MdUp | LgUp | XlUp | X2lUp
            SchemeCond = AnyScheme | LightOnly | DarkOnly
            MotionCond = AnyMotion | MotionSafeOnly | MotionReduceOnly

            FlagReq = ReqAny | ReqOn | ReqOff

            StateCond = (Style.FlagReq hovered,
                         Style.FlagReq focused,
                         Style.FlagReq active,
                         Style.FlagReq selected,
                         Style.FlagReq disabled) unique

            Cond = (Style.BpCond bp,
                    Style.SchemeCond scheme,
                    Style.MotionCond motion,
                    Style.StateCond state) unique

            Atom = ADisplay(Style.Display value) unique
                 | AAxis(Style.Axis value) unique
                 | AWrap(Style.Wrap value) unique
                 | AJustify(Style.Justify value) unique
                 | AItems(Style.Items value) unique
                 | ASelf(Style.Self value) unique

                 | AGap(Style.Space value) unique
                 | AGapX(Style.Space value) unique
                 | AGapY(Style.Space value) unique

                 | APad(Style.Space value) unique
                 | APadX(Style.Space value) unique
                 | APadY(Style.Space value) unique
                 | APadTop(Style.Space value) unique
                 | APadRight(Style.Space value) unique
                 | APadBottom(Style.Space value) unique
                 | APadLeft(Style.Space value) unique

                 | AMargin(Style.Space value) unique
                 | AMarginX(Style.Space value) unique
                 | AMarginY(Style.Space value) unique
                 | AMarginTop(Style.Space value) unique
                 | AMarginRight(Style.Space value) unique
                 | AMarginBottom(Style.Space value) unique
                 | AMarginLeft(Style.Space value) unique
                 | AMarginAutoX
                 | AMarginAutoLeft
                 | AMarginAutoRight

                 | AWidth(Style.Length value) unique
                 | AHeight(Style.Length value) unique
                 | AMinWidth(Style.Length value) unique
                 | AMaxWidth(Style.Length value) unique
                 | AMinHeight(Style.Length value) unique
                 | AMaxHeight(Style.Length value) unique

                 | AGrow(number value) unique
                 | AShrink(number value) unique
                 | ABasis(Style.Basis value) unique

                 | AFg(Style.ColorRef value) unique
                 | ABg(Style.ColorRef value) unique
                 | ABorderColor(Style.ColorRef value) unique
                 | ABorderWidth(Style.BorderW value) unique
                 | ARounded(Style.Radius value) unique
                 | AOpacity(Style.Opacity value) unique

                 | ATextSize(Style.FontSize value) unique
                 | ATextWeight(Style.FontWeight value) unique
                 | ATextAlign(Style.TextAlign value) unique
                 | ALeading(Style.Leading value) unique
                 | ATracking(Style.Tracking value) unique

                 | AOverflowX(Style.Overflow value) unique
                 | AOverflowY(Style.Overflow value) unique
                 | ACursor(Style.Cursor value) unique

                 | ACols(Style.Track* tracks) unique
                 | ARows(Style.Track* tracks) unique
                 | AColGap(Style.Space value) unique
                 | ARowGap(Style.Space value) unique

                 | AColStart(number value) unique
                 | AColSpan(number value) unique
                 | ARowStart(number value) unique
                 | ARowSpan(number value) unique

            Token = (Style.Cond cond,
                     Style.Atom atom) unique

            TokenList = (Style.Token* items) unique
            Group = (Style.Token* items) unique

            State = (boolean hovered,
                     boolean focused,
                     boolean active,
                     boolean selected,
                     boolean disabled) unique
        }

        module Paint {
            Stroke = (number rgba8,
                      number width) unique

            Fill = NoFill
                 | SolidFill(number rgba8) unique

            MeshMode = MeshTriangles | MeshStrip | MeshFan

            Vertex = (number x,
                      number y,
                      number u,
                      number v) unique

            Program = Line(number x1,
                           number y1,
                           number x2,
                           number y2,
                           Paint.Stroke stroke) unique

                    | Polyline(number* xy,
                               Paint.Stroke stroke) unique

                    | Polygon(number* xy,
                              Paint.Fill fill,
                              Paint.Stroke? stroke) unique

                    | Circle(number cx,
                             number cy,
                             number r,
                             Paint.Fill fill,
                             Paint.Stroke? stroke) unique

                    | Arc(number cx,
                          number cy,
                          number r,
                          number a1,
                          number a2,
                          number segments,
                          Paint.Stroke stroke) unique

                    | Bezier(number* xy,
                             number segments,
                             Paint.Stroke stroke) unique

                    | Mesh(Paint.MeshMode mode,
                           Paint.Vertex* vertices,
                           Core.Id? image_id,
                           number tint_rgba8,
                           number opacity) unique

                    | Image(Core.Id image_id,
                            number src_x,
                            number src_y,
                            number src_w,
                            number src_h,
                            number tint_rgba8,
                            number opacity) unique

            ProgramList = (Paint.Program* items) unique
        }

        module Interact {
            Role = Passive | HitTarget | FocusTarget | ActivateTarget | EditTarget
            FocusPolicy = FocusWrap | FocusClamp | FocusTrap | FocusPassthrough
            LayerKind = LayerBase | LayerOverlay | LayerPopup | LayerTooltip | LayerModal | LayerDragPreview
            OverlayPlacement = PlaceAuto | PlaceAbove | PlaceBelow | PlaceLeft | PlaceRight | PlaceCenter
        }

        module Auth {
            Node = Box(Core.Id id,
                       Style.TokenList styles,
                       Auth.Node* children) unique
                 | Text(Core.Id id,
                        Style.TokenList styles,
                        string content) unique
                 | TextRef(Core.Id id,
                           Style.TokenList styles,
                           Core.Id content_id) unique
                 | Paint(Core.Id id,
                         Style.TokenList styles,
                         Paint.ProgramList paint) unique
                 | Scroll(Core.Id id,
                          Style.TokenList styles,
                          Style.ScrollAxis axis,
                          Auth.Node child) unique
                 | WithState(Style.State state,
                             Auth.Node child) unique
                 | WithInput(Core.Id id,
                             Interact.Role role,
                             Auth.Node child) unique
                 | WithDragSource(Core.Id id,
                                  Auth.Node child) unique
                 | WithDropTarget(Core.Id id,
                                  Auth.Node child) unique
                 | WithDropSlot(Core.Id id,
                                Auth.Node child) unique
                 | FocusScope(Core.Id id,
                              Interact.FocusPolicy policy,
                              Auth.Node child) unique
                 | Layer(Core.Id id,
                         Interact.LayerKind kind,
                         number order,
                         Auth.Node child) unique
                 | Overlay(Core.Id id,
                           Core.Id anchor_id,
                           Interact.OverlayPlacement placement,
                           boolean modal,
                           Auth.Node child) unique
                 | Modal(Core.Id id,
                         Auth.Node child) unique
                 | Fragment(Auth.Node* children) unique
                 | Empty unique
        }

        module Compose {
            Node = Raw(Auth.Node child) unique
                 | Fragment(Compose.Node* children) unique
                 | Panel(Core.Id id,
                         Style.TokenList? styles,
                         Style.TokenList? header_styles,
                         Compose.Node? header,
                         Style.TokenList? body_styles,
                         Compose.Node? body,
                         Style.TokenList? footer_styles,
                         Compose.Node? footer) unique
                 | ScrollPanel(Core.Id id,
                               Style.TokenList? styles,
                               Style.TokenList? header_styles,
                               Compose.Node? header,
                               Core.Id scroll_id,
                               Style.ScrollAxis axis,
                               Style.TokenList? scroll_styles,
                               Style.TokenList? body_styles,
                               Compose.Node? body,
                               Style.TokenList? footer_styles,
                               Compose.Node? footer) unique
                 | HSplit(Core.Id id,
                          Style.TokenList? styles,
                          Compose.Node* children) unique
                 | VSplit(Core.Id id,
                          Style.TokenList? styles,
                          Compose.Node* children) unique
                 | Workbench(Core.Id id,
                             Style.TokenList? styles,
                             Style.TokenList? top_styles,
                             Compose.Node? top,
                             Style.TokenList? middle_styles,
                             Style.TokenList? left_styles,
                             Compose.Node? left,
                             Style.TokenList? center_styles,
                             Compose.Node center,
                             Style.TokenList? right_styles,
                             Compose.Node? right,
                             Style.TokenList? bottom_styles,
                             Compose.Node? bottom) unique
        }
    ]]
    return T
end

M.T = M.Define(pvm.context())
M.B = M.T:FastBuilders()

return M
