module EditZkNote exposing
    ( Command(..)
    , Model
    , Msg(..)
    , compareZklinks
    , dirty
    , gotId
    , gotSelectedText
    , initFull
    , initNew
    , noteLink
    , onCtrlS
    , pageLink
    , replaceOrAdd
    , saveZkLinkList
    , showZkl
    , sznFromModel
    , toPubId
    , update
    , updateSearchResult
    , view
    , zkLinkName
    , zklKey
    )

import CellCommon exposing (..)
import Cellme.Cellme exposing (Cell, CellContainer(..), CellState, RunState(..), evalCellsFully, evalCellsOnce)
import Cellme.DictCellme exposing (CellDict(..), DictCell, dictCcr, getCd, mkCc)
import Common
import Data exposing (Direction(..))
import Dialog as D
import Dict exposing (Dict)
import Element as E exposing (Element)
import Element.Background as EBk
import Element.Border as EBd
import Element.Font as EF
import Element.Input as EI
import Element.Region as ER
import Html exposing (Attribute, Html)
import Html.Attributes
import Markdown.Block as Block exposing (Block, Inline, ListItem(..), Task(..), inlineFoldl)
import Markdown.Html
import Markdown.Parser
import Markdown.Renderer
import Schelme.Show exposing (showTerm)
import Search as S
import SearchPanel as SP
import TangoColors as TC
import Url as U
import Url.Builder as UB
import Url.Parser as UP exposing ((</>))
import Util
import ZkCommon as ZC


type Msg
    = OnMarkdownInput String
    | OnSchelmeCodeChanged String String
    | OnTitleChanged String
    | OnPubidChanged String
    | SavePress
    | DonePress
    | RevertPress
    | DeletePress
    | ViewPress
    | NewPress
    | CopyPress
    | SwitchPress Int
    | ToLinkPress Data.ZkListNote
    | FromLinkPress Data.ZkListNote
    | PublicPress Bool
    | RemoveLink EditLink
    | MdLink EditLink
    | SPMsg SP.Msg
    | NavChoiceChanged NavChoice
    | DialogMsg D.Msg
    | RestoreSearch String
    | Noop


type NavChoice
    = NcEdit
    | NcView
    | NcSearch


type alias EditLink =
    { otherid : Int
    , direction : Direction
    , user : Int
    , zknote : Maybe Int
    , othername : Maybe String
    , delete : Maybe Bool
    }


type WClass
    = Narrow
    | Medium
    | Wide


type alias Model =
    { id : Maybe Int
    , ld : Data.LoginData
    , noteUser : Int
    , noteUserName : String
    , zknSearchResult : Data.ZkNoteSearchResult
    , focusSr : Maybe Int -- note id in search result.
    , zklDict : Dict String EditLink
    , editable : Bool
    , pubidtxt : String
    , title : String
    , md : String
    , cells : CellDict
    , revert : Maybe Data.SaveZkNote
    , initialZklDict : Dict String EditLink
    , spmodel : SP.Model
    , navchoice : NavChoice
    , dialog : Maybe D.Model
    }


type Command
    = None
    | Save Data.SaveZkNotePlusLinks
    | SaveExit Data.SaveZkNotePlusLinks
    | Revert
    | View Data.SaveZkNote
    | Delete Int
    | Switch Int
    | SaveSwitch Data.SaveZkNotePlusLinks Int
    | GetSelectedText (List String)
    | Search S.ZkNoteSearch


elToSzl : EditLink -> Data.SaveZkLink
elToSzl el =
    { otherid = el.otherid
    , direction = el.direction
    , user = el.user
    , zknote = el.zknote
    , delete = el.delete
    }


elToSzkl : Int -> EditLink -> Data.ZkLink
elToSzkl this el =
    case el.direction of
        From ->
            { from = this
            , to = el.otherid
            , user = el.user
            , zknote = Nothing
            , fromname = Nothing
            , toname = Nothing
            , delete = Nothing
            }

        To ->
            { from = el.otherid
            , to = this
            , user = el.user
            , zknote = Nothing
            , fromname = Nothing
            , toname = Nothing
            , delete = Nothing
            }


sznFromModel : Model -> Data.SaveZkNote
sznFromModel model =
    { id = model.id
    , title = model.title
    , content = model.md
    , pubid = toPubId (isPublic model) model.pubidtxt
    }


fullSave : Model -> Data.SaveZkNotePlusLinks
fullSave model =
    { note = sznFromModel model
    , links = saveZkLinkList model
    }


saveZkLinkList : Model -> List Data.SaveZkLink
saveZkLinkList model =
    List.map
        (\zkl -> { zkl | delete = Nothing })
        (List.map elToSzl (Dict.values (Dict.diff model.zklDict model.initialZklDict)))
        ++ List.map
            (\zkl -> { zkl | delete = Just True })
            (List.map elToSzl (Dict.values (Dict.diff model.initialZklDict model.zklDict)))


updateSearchResult : Data.ZkNoteSearchResult -> Model -> Model
updateSearchResult zsr model =
    { model
        | zknSearchResult = zsr
        , spmodel = SP.searchResultUpdated zsr model.spmodel
    }


toPubId : Bool -> String -> Maybe String
toPubId public pubidtxt =
    if public && pubidtxt /= "" then
        Just pubidtxt

    else
        Nothing


zkLinkName : Data.ZkLink -> Int -> String
zkLinkName zklink noteid =
    if noteid == zklink.from then
        zklink.toname |> Maybe.withDefault (String.fromInt zklink.to)

    else if noteid == zklink.to then
        zklink.fromname |> Maybe.withDefault (String.fromInt zklink.from)

    else
        "link error"


dirty : Model -> Bool
dirty model =
    model.revert
        |> Maybe.map
            (\r ->
                not <|
                    (r.id == model.id)
                        && (r.pubid == toPubId (isPublic model) model.pubidtxt)
                        && (r.title == model.title)
                        && (r.content == model.md)
                        && (Dict.keys model.zklDict == Dict.keys model.initialZklDict)
            )
        |> Maybe.withDefault True


showZkl : Bool -> Bool -> Int -> Maybe Int -> EditLink -> Element Msg
showZkl isDirty editable user id zkl =
    let
        ( dir, otherid ) =
            case zkl.direction of
                To ->
                    ( E.text "→", Just zkl.otherid )

                From ->
                    ( E.text "←", Just zkl.otherid )
    in
    E.row [ E.spacing 8, E.width E.fill ]
        [ case otherid of
            Just zknoteid ->
                EI.button (mkButtonStyle linkButtonStyle isDirty ++ [ E.alignRight ]) { onPress = Just (SwitchPress zknoteid), label = E.text "↗" }

            Nothing ->
                E.none
        , if editable then
            EI.button (linkButtonStyle ++ [ E.alignLeft ])
                { onPress = Just (MdLink zkl)
                , label = E.text "^"
                }

          else
            EI.button (disabledLinkButtonStyle ++ [ E.alignLeft ])
                { onPress = Nothing
                , label = E.text "^"
                }
        , if user == zkl.user then
            EI.button (linkButtonStyle ++ [ E.alignLeft ])
                { onPress = Just (RemoveLink zkl)
                , label = E.text "X"
                }

          else
            EI.button (linkButtonStyle ++ [ E.alignLeft, EBk.color TC.darkGray ])
                { onPress = Nothing
                , label = E.text "X"
                }
        , dir
        , zkl.othername
            |> Maybe.withDefault ""
            |> (\s ->
                    -- TODO: focus link.  touch text, get buttons.
                    -- maybe keep 'open' button tho.  Make it a link?
                    -- larger buttons too.
                    --
                    -- do the same thing in search results!
                    E.row
                        [ E.clipX
                        , E.centerY
                        , E.height E.fill
                        , E.width E.fill
                        ]
                        [ E.text s
                        ]
                -- E.link
                -- ((if isDirty then
                --     ZC.saveLinkStyle
                --   else
                --     ZC.myLinkStyle
                --  )
                --     ++ [ E.clipX, E.width E.fill, E.height E.fill, E.centerY ]
                -- )
                -- { url = Data.editNoteLink zkl.otherid
                -- , label = E.row [ E.clipX, E.width E.fill, E.height E.shrink ] [ E.text s ]
                -- }
               )
        ]


pageLink : Model -> Maybe String
pageLink model =
    model.id
        |> Maybe.andThen
            (\id ->
                toPubId (isPublic model) model.pubidtxt
                    |> Maybe.map
                        (\pubid ->
                            UB.absolute [ "page", pubid ] []
                        )
                    |> Util.mapNothing
                        (UB.absolute [ "editnote", String.fromInt id ] [])
            )


view : Util.Size -> Model -> Element Msg
view size model =
    case model.dialog of
        Just dialog ->
            D.view size dialog |> E.map DialogMsg

        Nothing ->
            zknview size model


commonButtonStyle : Bool -> List (E.Attribute msg)
commonButtonStyle isDirty =
    mkButtonStyle Common.buttonStyle isDirty


mkButtonStyle : List (E.Attribute msg) -> Bool -> List (E.Attribute msg)
mkButtonStyle style isdirty =
    if isdirty then
        style ++ [ EBk.color TC.darkYellow ]

    else
        style


linkButtonStyle =
    Common.buttonStyle ++ [ E.paddingXY 2 2, E.centerY ]


disabledLinkButtonStyle =
    Common.disabledButtonStyle ++ [ E.paddingXY 2 2, E.centerY ]


showSr : Model -> Bool -> Data.ZkListNote -> Element Msg
showSr =
    \model isdirty zkln ->
        let
            lnnonme =
                zkln.user /= model.ld.userid
        in
        E.row [ E.spacing 8, E.width E.fill ]
            [ (case
                Dict.get (zklKey { direction = To, otherid = zkln.id })
                    model.zklDict
               of
                Just _ ->
                    Nothing

                Nothing ->
                    Just 1
              )
                |> Maybe.map
                    (\_ ->
                        EI.button linkButtonStyle
                            { onPress = Just <| ToLinkPress zkln
                            , label = E.el [ E.centerY ] <| E.text "→"
                            }
                    )
                |> Maybe.withDefault
                    (EI.button
                        disabledLinkButtonStyle
                        { onPress = Nothing
                        , label = E.el [ E.centerY ] <| E.text "→"
                        }
                    )
            , (case
                Dict.get (zklKey { direction = From, otherid = zkln.id })
                    model.zklDict
               of
                Just _ ->
                    Nothing

                Nothing ->
                    Just 1
              )
                |> Maybe.map
                    (\_ ->
                        EI.button linkButtonStyle
                            { onPress = Just <| FromLinkPress zkln
                            , label = E.el [ E.centerY ] <| E.text "←"
                            }
                    )
                |> Maybe.withDefault
                    (EI.button
                        disabledLinkButtonStyle
                        { onPress = Nothing
                        , label = E.el [ E.centerY ] <| E.text "←"
                        }
                    )

            {- , EI.button
               (case ( isdirty, lnnonme ) of
                   ( True, True ) ->
                       dirtybutton

                   ( False, True ) ->
                       Common.buttonStyle ++ [ EBk.color TC.lightBlue ]

                   _ ->
                       dirtybutton
               )
               { onPress =
                   Just (SwitchPress zkln.id)
               , label =
                   if lnnonme then
                       E.text "show"

                   else
                       E.text "edit"
               }
            -}
            , E.row
                [ E.clipX
                , E.height E.fill
                , E.width E.fill
                ]
                [ if lnnonme then
                    E.link
                        (if isdirty then
                            ZC.saveLinkStyle

                         else
                            ZC.otherLinkStyle
                        )
                        { url = Data.editNoteLink zkln.id
                        , label = E.text zkln.title
                        }

                  else
                    E.link
                        (if isdirty then
                            ZC.saveLinkStyle

                         else
                            ZC.myLinkStyle
                        )
                        { url = Data.editNoteLink zkln.id
                        , label = E.text zkln.title
                        }
                ]
            ]


zknview : Util.Size -> Model -> Element Msg
zknview size model =
    let
        wclass =
            if size.width < 800 then
                Narrow

            else if size.width > 1700 then
                Wide

            else
                Medium

        isdirty =
            dirty model

        perhapsdirtybutton =
            commonButtonStyle isdirty

        editable =
            model.editable

        showLinks =
            E.row [ EF.bold ] [ E.text "links" ]
                :: List.map
                    (showZkl isdirty editable model.ld.userid model.id)
                    (Dict.values model.zklDict)

        mdedit =
            E.column
                [ E.spacing 8
                , E.alignTop
                , E.width
                    (case wclass of
                        Narrow ->
                            E.fill

                        Medium ->
                            E.fill

                        Wide ->
                            E.fill
                    )
                , E.paddingXY 25 0
                ]
                (EI.multiline
                    [ if editable then
                        EF.color TC.black

                      else
                        EF.color TC.darkGrey
                    , E.htmlAttribute (Html.Attributes.id "mdtext")
                    , E.alignTop
                    ]
                    { onChange =
                        if editable then
                            OnMarkdownInput

                        else
                            always Noop
                    , text = model.md
                    , placeholder = Nothing
                    , label = EI.labelHidden "Markdown input"
                    , spellcheck = False
                    }
                    -- show the links.
                    :: showLinks
                )

        public =
            isPublic model

        -- super lame math because images suck in html/elm-ui
        mdw =
            min 1000
                (case wclass of
                    Narrow ->
                        size.width

                    Medium ->
                        size.width - 400 - 8

                    Wide ->
                        size.width - 400 - 500 - 16
                )
                - (60 * 2 + 6)

        mdview =
            case markdownView (mkRenderer RestoreSearch mdw model.cells OnSchelmeCodeChanged) model.md of
                Ok rendered ->
                    E.column
                        [ E.width E.fill
                        , E.centerX
                        , E.alignTop
                        , E.spacing 8
                        ]
                    <|
                        [ E.column
                            [ E.centerX
                            , E.paddingXY 30 15
                            , E.spacing 8
                            , EBk.color TC.lightGrey
                            ]
                            [ E.paragraph [] [ E.text model.title ]
                            , E.column
                                [ E.spacing 30
                                , E.padding 20
                                , E.width (E.fill |> E.maximum 1000)
                                , E.centerX
                                , E.alignTop
                                , EBd.width 3
                                , EBd.color TC.darkGrey
                                ]
                                rendered
                            ]
                        ]
                            ++ (if wclass == Wide then
                                    []

                                else
                                    showLinks
                               )

                Err errors ->
                    E.text errors

        parabuttonstyle =
            Common.buttonStyle ++ [ E.paddingXY 10 0 ]

        perhapsdirtyparabuttonstyle =
            perhapsdirtybutton ++ [ E.paddingXY 10 0 ]

        searchPanel =
            let
                spwidth =
                    case wclass of
                        Narrow ->
                            E.fill

                        Medium ->
                            E.px 400

                        Wide ->
                            E.px 400
            in
            E.column
                [ E.spacing 8
                , E.alignTop
                , E.alignRight
                , E.width spwidth
                ]
                ((E.map SPMsg <|
                    SP.view True (wclass == Narrow) 0 model.spmodel
                 )
                    :: (List.map
                            (showSr model isdirty)
                        <|
                            case model.id of
                                Just id ->
                                    List.filter (\zkl -> zkl.id /= id) model.zknSearchResult.notes

                                Nothing ->
                                    model.zknSearchResult.notes
                       )
                )

        showpagelink =
            case pageLink model of
                Just pl ->
                    E.link Common.linkStyle { url = pl, label = E.text pl }

                Nothing ->
                    E.none
    in
    E.column
        [ E.width E.fill, E.spacing 8, E.padding 8 ]
        [ E.row [ E.width E.fill, E.spacing 8 ]
            [ E.row [ EF.bold ] [ E.text model.ld.name ]
            , if editable then
                EI.button (E.alignRight :: Common.buttonStyle) { onPress = Just DeletePress, label = E.text "delete" }

              else
                EI.button (E.alignRight :: Common.disabledButtonStyle) { onPress = Nothing, label = E.text "delete" }
            ]
        , E.paragraph
            [ E.width E.fill, E.spacingXY 3 17 ]
          <|
            List.intersperse (E.text " ")
                [ EI.button
                    perhapsdirtyparabuttonstyle
                    { onPress = Just DonePress, label = E.text "done" }
                , EI.button parabuttonstyle { onPress = Just RevertPress, label = E.text "cancel" }
                , EI.button parabuttonstyle { onPress = Just ViewPress, label = E.text "view" }
                , EI.button parabuttonstyle { onPress = Just CopyPress, label = E.text "copy" }

                -- , EI.button parabuttonstyle { onPress = Just LinksPress, label = E.text"links" }
                , case isdirty of
                    True ->
                        EI.button perhapsdirtyparabuttonstyle { onPress = Just SavePress, label = E.text "save" }

                    False ->
                        E.none
                , EI.button perhapsdirtyparabuttonstyle { onPress = Just NewPress, label = E.text "new" }
                ]
        , EI.text
            (if editable then
                [ E.htmlAttribute (Html.Attributes.id "title")
                ]

             else
                [ EF.color TC.darkGrey, E.htmlAttribute (Html.Attributes.id "title") ]
            )
            { onChange =
                if editable then
                    OnTitleChanged

                else
                    always Noop
            , text = model.title
            , placeholder = Nothing
            , label = EI.labelLeft [] (E.text "title")
            }
        , if model.noteUser == model.ld.userid then
            E.none

          else
            E.row [ E.spacing 8 ] [ E.text "creator", E.row [ EF.bold ] [ E.text model.noteUserName ] ]
        , E.row [ E.spacing 8, E.width E.fill ]
            [ EI.checkbox [ E.width E.shrink ]
                { onChange =
                    if editable then
                        PublicPress

                    else
                        always Noop
                , icon = EI.defaultCheckbox
                , checked = public
                , label = EI.labelLeft [] (E.text "public")
                }
            , if public then
                EI.text [ E.width E.fill ]
                    { onChange =
                        if editable then
                            OnPubidChanged

                        else
                            always Noop
                    , text = model.pubidtxt
                    , placeholder = Nothing
                    , label = EI.labelLeft [] (E.text "article id")
                    }

              else
                E.none
            , if wclass /= Narrow then
                showpagelink

              else
                E.none
            ]
        , if wclass == Narrow then
            showpagelink

          else
            E.none
        , case wclass of
            Wide ->
                E.row
                    [ E.width E.fill
                    , E.spacing 8
                    , E.alignTop
                    ]
                    [ mdedit, mdview, searchPanel ]

            Medium ->
                E.row [ E.width E.fill, E.spacing 8 ]
                    [ E.column [ E.width E.fill, E.alignTop ]
                        [ Common.navbar 2
                            (if model.navchoice == NcSearch then
                                NcView

                             else
                                model.navchoice
                            )
                            NavChoiceChanged
                            [ ( NcView, "view" )
                            , ( NcEdit
                              , if editable then
                                    "edit"

                                else
                                    "markdown"
                              )
                            ]
                        , case model.navchoice of
                            NcEdit ->
                                mdedit

                            NcView ->
                                mdview

                            NcSearch ->
                                mdview
                        ]
                    , searchPanel
                    ]

            Narrow ->
                E.column [ E.width E.fill ]
                    [ Common.navbar 2
                        model.navchoice
                        NavChoiceChanged
                        [ ( NcView, "view" )
                        , ( NcEdit
                          , if editable then
                                "edit"

                            else
                                "markdown"
                          )
                        , ( NcSearch, "search" )
                        ]
                    , case model.navchoice of
                        NcEdit ->
                            mdedit

                        NcView ->
                            mdview

                        NcSearch ->
                            searchPanel
                    ]
        ]


zklKey : { a | otherid : Int, direction : Direction } -> String
zklKey zkl =
    String.fromInt zkl.otherid
        ++ ":"
        ++ (case zkl.direction of
                From ->
                    "from"

                To ->
                    "to"
           )


linksWith : List EditLink -> Int -> Bool
linksWith links linkid =
    Util.trueforany (\l -> l.otherid == linkid) links


isPublic : Model -> Bool
isPublic model =
    linksWith (Dict.values model.zklDict) model.ld.publicid


toEditLink : Int -> Data.ZkLink -> EditLink
toEditLink id zkl =
    let
        ( oid, direction ) =
            if zkl.to == id then
                ( zkl.from, To )

            else
                ( zkl.to, From )
    in
    { otherid = oid
    , direction = direction
    , user = zkl.user
    , zknote = zkl.zknote
    , othername = Just <| zkLinkName zkl id
    , delete = zkl.delete
    }


initFull : Data.LoginData -> Data.ZkNoteSearchResult -> Data.ZkNote -> Data.ZkLinks -> SP.Model -> Model
initFull ld zkl zknote zklDict spm =
    let
        cells =
            zknote.content
                |> mdCells
                |> Result.withDefault (CellDict Dict.empty)

        ( cc, result ) =
            evalCellsFully
                (mkCc cells)

        links =
            List.map (toEditLink zknote.id) zklDict.links
    in
    { id = Just zknote.id
    , ld = ld
    , noteUser = zknote.user
    , noteUserName = zknote.username
    , zknSearchResult = zkl
    , focusSr = Nothing
    , zklDict = Dict.fromList (List.map (\zl -> ( zklKey zl, zl )) links)
    , initialZklDict =
        Dict.fromList
            (List.map
                (\zl -> ( zklKey zl, zl ))
                links
            )
    , pubidtxt = zknote.pubid |> Maybe.withDefault ""
    , title = zknote.title
    , md = zknote.content
    , editable = zknote.editable
    , cells = getCd cc
    , revert = Just (Data.saveZkNote zknote)
    , spmodel = SP.searchResultUpdated zkl spm
    , navchoice = NcView
    , dialog = Nothing
    }


initNew : Data.LoginData -> Data.ZkNoteSearchResult -> SP.Model -> Model
initNew ld zkl spm =
    let
        cells =
            ""
                |> mdCells
                |> Result.withDefault (CellDict Dict.empty)

        ( cc, result ) =
            evalCellsFully
                (mkCc cells)
    in
    { id = Nothing
    , ld = ld
    , noteUser = ld.userid
    , noteUserName = ld.name
    , zknSearchResult = zkl
    , focusSr = Nothing
    , zklDict = Dict.empty
    , initialZklDict = Dict.empty
    , pubidtxt = ""
    , title = ""
    , editable = True
    , md = ""
    , cells = getCd cc
    , revert = Nothing
    , spmodel = SP.searchResultUpdated zkl spm
    , navchoice = NcEdit
    , dialog = Nothing
    }


replaceOrAdd : List a -> a -> (a -> a -> Bool) -> (a -> a -> a) -> List a
replaceOrAdd items replacement compare mergef =
    case items of
        l :: r ->
            if compare l replacement then
                mergef l replacement :: r

            else
                l :: replaceOrAdd r replacement compare mergef

        [] ->
            [ replacement ]



{- addListNote : Model -> Int -> Data.SaveZkNote -> Data.SavedZkNote -> Model
   addListNote model uid szn szkn =
       let
           zln =
               { id = szkn.id
               , user = uid
               , title = szn.title
               , createdate = szkn.changeddate
               , changeddate = szkn.changeddate
               }
       in
       { model
           | zknSearchResult =
               model.zknSearchResult
                   |> (\zsr ->
                           { zsr
                               | notes =
                                   replaceOrAdd model.zknSearchResult.notes
                                       zln
                                       (\a b -> a.id == b.id)
                                       (\a b -> { b | createdate = a.createdate })
                           }
                      )
       }

-}


gotId : Model -> Int -> Model
gotId model id =
    let
        -- if we already have an ID, keep it.
        m1 =
            { model | id = Just (model.id |> Maybe.withDefault id) }
    in
    { m1 | revert = Just <| sznFromModel m1 }


gotSelectedText : Model -> String -> ( Model, Command )
gotSelectedText model s =
    let
        nmod =
            initNew model.ld model.zknSearchResult model.spmodel
    in
    ( { nmod | title = s }
    , if dirty model then
        Save
            (fullSave model)

      else
        None
    )


noteLink : String -> Maybe Int
noteLink str =
    -- hack allows parsing /note/<N>
    -- other urls will be invalid which is fine.
    U.fromString ("http://wat" ++ str)
        |> Maybe.andThen
            (UP.parse (UP.s "note" </> UP.int))


compareZklinks : Data.ZkLink -> Data.ZkLink -> Order
compareZklinks left right =
    case compare left.from right.from of
        EQ ->
            compare left.to right.to

        ltgt ->
            ltgt


onCtrlS : Model -> ( Model, Command )
onCtrlS model =
    if dirty model then
        update SavePress model

    else
        ( model, None )


update : Msg -> Model -> ( Model, Command )
update msg model =
    case msg of
        RestoreSearch s ->
            let
                spmodel =
                    SP.setSearchString model.spmodel s
            in
            ( { model | spmodel = spmodel }
            , SP.getSearch spmodel
                |> Maybe.map Search
                |> Maybe.withDefault None
            )

        SavePress ->
            -- TODO more reliability.  What if the save fails?
            let
                saveZkn =
                    sznFromModel model
            in
            ( { model
                | revert = Just saveZkn
                , initialZklDict = model.zklDict
              }
            , Save
                (fullSave model)
            )

        DonePress ->
            ( model
            , if dirty model then
                SaveExit
                    (fullSave model)

              else
                Revert
            )

        CopyPress ->
            ( { model
                | id = Nothing
                , title = "Copy of " ++ model.title
                , pubidtxt = "" -- otherwise we get a conflict on save.
                , zklDict =
                    model.zklDict
                        |> Dict.remove (zklKey { otherid = model.ld.publicid, direction = To })
                        |> Dict.remove (zklKey { otherid = model.ld.publicid, direction = From })
                , initialZklDict = Dict.empty
              }
            , None
            )

        ViewPress ->
            ( model
            , View
                (sznFromModel model)
            )

        {- LinksPress ->
           let
               blah =
                   model.md
                       |> Markdown.Parser.parse
                       |> Result.mapError (\error -> error |> List.map Markdown.Parser.deadEndToString |> String.join "\n")

               zklDict =
                   case ( blah, model.id ) of
                       ( Err _, _ ) ->
                           Dict.empty

                       ( Ok blocks, Nothing ) ->
                           Dict.empty

                       ( Ok blocks, Just id ) ->
                           inlineFoldl
                               (\inline links ->
                                   case inline of
                                       Block.Link str mbstr moarinlines ->
                                           case noteLink str of
                                               Just rid ->
                                                   let
                                                       zkl =
                                                           { from = id
                                                           , to = rid
                                                           , user = model.ld.userid
                                                           , zknote = Nothing
                                                           , fromname = Nothing
                                                           , toname = mbstr
                                                           , delete = Nothing
                                                           }
                                                   in
                                                   ( zklKey zkl, zkl )
                                                       :: links

                                               Nothing ->
                                                   links

                                       _ ->
                                           links
                               )
                               []
                               blocks
                               |> Dict.fromList
           in
           ( { model | zklDict = Dict.union model.zklDict zklDict }, None )

        -}
        NewPress ->
            ( model
            , GetSelectedText [ "title", "mdtext" ]
            )

        ToLinkPress zkln ->
            let
                nzkl =
                    { direction = To
                    , otherid = zkln.id
                    , user = model.ld.userid
                    , zknote = Nothing
                    , othername = Just zkln.title
                    , delete = Nothing
                    }
            in
            ( { model
                | zklDict = Dict.insert (zklKey nzkl) nzkl model.zklDict
              }
            , None
            )

        FromLinkPress zkln ->
            let
                nzkl =
                    { direction = From
                    , otherid = zkln.id
                    , user = model.ld.userid
                    , zknote = Nothing
                    , othername = Just zkln.title
                    , delete = Nothing
                    }
            in
            ( { model
                | zklDict = Dict.insert (zklKey nzkl) nzkl model.zklDict
              }
            , None
            )

        RemoveLink zkln ->
            ( { model
                | zklDict = Dict.remove (zklKey zkln) model.zklDict
              }
            , None
            )

        MdLink zkln ->
            let
                ( title, id ) =
                    ( zkln.othername |> Maybe.withDefault "", zkln.otherid )
            in
            ( { model
                | md =
                    model.md
                        ++ (if model.md == "" then
                                "["

                            else
                                "\n\n["
                           )
                        ++ title
                        ++ "]("
                        ++ "/note/"
                        ++ String.fromInt id
                        ++ ")"
              }
            , None
            )

        SwitchPress id ->
            if dirty model then
                ( model, SaveSwitch (fullSave model) id )

            else
                ( model, Switch id )

        PublicPress _ ->
            case model.id of
                Nothing ->
                    ( model, None )

                Just id ->
                    if isPublic model then
                        ( { model
                            | zklDict =
                                model.zklDict
                                    |> Dict.remove (zklKey { direction = From, otherid = model.ld.publicid })
                                    |> Dict.remove (zklKey { direction = To, otherid = model.ld.publicid })
                          }
                        , None
                        )

                    else
                        let
                            nzkl =
                                { direction = To
                                , otherid = model.ld.publicid
                                , user = model.ld.userid
                                , zknote = Nothing
                                , othername = Just "public"
                                , delete = Nothing
                                }
                        in
                        ( { model
                            | zklDict = Dict.insert (zklKey nzkl) nzkl model.zklDict
                          }
                        , None
                        )

        RevertPress ->
            ( model, Revert )

        DeletePress ->
            ( { model
                | dialog =
                    Just <|
                        D.init "delete this note?"
                            True
                            (\size -> E.map (\_ -> ()) (view size model))
              }
            , None
            )

        DialogMsg dm ->
            case model.dialog of
                Just dmod ->
                    case ( D.update dm dmod, model.id ) of
                        ( D.Cancel, _ ) ->
                            ( { model | dialog = Nothing }, None )

                        ( D.Ok, Nothing ) ->
                            ( { model | dialog = Nothing }, None )

                        ( D.Ok, Just id ) ->
                            ( { model | dialog = Nothing }, Delete id )

                        ( D.Dialog dmod2, _ ) ->
                            ( { model | dialog = Just dmod2 }, None )

                Nothing ->
                    ( model, None )

        OnTitleChanged t ->
            ( { model | title = t }, None )

        OnPubidChanged t ->
            ( { model | pubidtxt = t }, None )

        OnMarkdownInput newMarkdown ->
            let
                cells =
                    newMarkdown
                        |> mdCells
                        |> Result.withDefault (CellDict Dict.empty)

                ( cc, result ) =
                    evalCellsFully
                        (mkCc cells)
            in
            ( { model
                | md = newMarkdown
                , cells = getCd cc
              }
            , None
            )

        OnSchelmeCodeChanged name string ->
            let
                (CellDict cd) =
                    model.cells

                ( cc, result ) =
                    evalCellsFully
                        (mkCc
                            (Dict.insert name (defCell string) cd
                                |> CellDict
                            )
                        )
            in
            ( { model
                | cells = getCd cc
              }
            , None
            )

        SPMsg m ->
            let
                ( nm, cm ) =
                    SP.update m model.spmodel

                mod =
                    { model | spmodel = nm }
            in
            case cm of
                SP.None ->
                    ( mod, None )

                SP.Save ->
                    ( mod, None )

                SP.Copy s ->
                    ( { mod
                        | md =
                            model.md
                                ++ (if model.md == "" then
                                        "<search query=\""

                                    else
                                        "\n\n<search query=\""
                                   )
                                ++ String.replace "&" "&amp;" s
                                ++ "\"/>"
                      }
                    , None
                    )

                SP.Search ts ->
                    ( mod, Search ts )

        NavChoiceChanged nc ->
            ( { model | navchoice = nc }, None )

        Noop ->
            ( model, None )
