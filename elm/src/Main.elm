port module Main exposing (main)

import Array
import Browser
import Browser.Events
import Browser.Navigation
import Cellme.Cellme exposing (Cell, CellContainer(..), CellState, RunState(..), evalCellsFully, evalCellsOnce)
import Cellme.DictCellme exposing (CellDict(..), DictCell, dictCcr, getCd, mkCc)
import Common exposing (buttonStyle)
import Data
import Dict exposing (Dict)
import DisplayMessage
import EditZkNote
import EditZkNoteListing
import Element as E exposing (Element)
import Element.Background as EBk
import Element.Border as EBd
import Element.Font as EF
import Element.Input as EI
import Element.Region
import File as F
import File.Select as FS
import GenDialog as GD
import Html exposing (Attribute, Html)
import Html.Attributes
import Html.Events as HE
import Http
import Http.Tasks as HT
import Import
import Json.Decode as JD
import Json.Encode as JE
import LocalStorage as LS
import Markdown.Block as Block exposing (Block, Inline, ListItem(..), Task(..))
import Markdown.Html
import Markdown.Parser
import Markdown.Renderer
import MdCommon as MC
import MessageNLink
import Orgauth.AdminInterface as AI
import Orgauth.ChangeEmail as CE
import Orgauth.ChangePassword as CP
import Orgauth.Data as OD
import Orgauth.Login as Login
import Orgauth.ResetPassword as ResetPassword
import Orgauth.UserEdit as UserEdit
import Orgauth.UserInterface as UI
import Orgauth.UserListing as UserListing
import PublicInterface as PI
import Random exposing (Seed, initialSeed)
import Route exposing (Route(..), parseUrl, routeTitle, routeUrl)
import Schelme.Show exposing (showTerm)
import Search as S
import SearchStackPanel as SP
import SelectString as SS
import ShowMessage
import TangoColors as TC
import Task exposing (Task)
import Time
import Toop
import UUID exposing (UUID)
import Url exposing (Url)
import Url.Builder as UB
import Url.Parser as UP exposing ((</>))
import UserSettings
import Util
import View
import WindowKeys
import ZkInterface as ZI


type Msg
    = LoginMsg Login.Msg
    | ViewMsg View.Msg
    | EditZkNoteMsg EditZkNote.Msg
    | EditZkNoteListingMsg EditZkNoteListing.Msg
    | UserSettingsMsg UserSettings.Msg
    | UserListingMsg UserListing.Msg
    | UserEditMsg UserEdit.Msg
    | ImportMsg Import.Msg
    | ShowMessageMsg ShowMessage.Msg
    | UserReplyData (Result Http.Error UI.ServerResponse)
    | AdminReplyData (Result Http.Error AI.ServerResponse)
    | ZkReplyData (Result Http.Error ZI.ServerResponse)
    | TAReplyData Data.TASelection (Result Http.Error ZI.ServerResponse)
    | PublicReplyData (Result Http.Error PI.ServerResponse)
    | ErrorIndexNote (Result Http.Error PI.ServerResponse)
    | LoadUrl String
    | InternalUrl Url
    | TASelection JD.Value
    | UrlChanged Url
    | WindowSize Util.Size
    | DisplayMessageMsg (GD.Msg DisplayMessage.Msg)
    | MessageNLinkMsg (GD.Msg MessageNLink.Msg)
    | SelectDialogMsg (GD.Msg (SS.Msg Int))
    | ChangePasswordDialogMsg (GD.Msg CP.Msg)
    | ChangeEmailDialogMsg (GD.Msg CE.Msg)
    | ResetPasswordMsg ResetPassword.Msg
    | Zone Time.Zone
    | WkMsg (Result JD.Error WindowKeys.Key)
    | ReceiveLocalVal { for : String, name : String, value : Maybe String }
    | Noop


type State
    = Login Login.Model
    | EditZkNote EditZkNote.Model Data.LoginData
    | EditZkNoteListing EditZkNoteListing.Model Data.LoginData
    | View View.Model
    | EView View.Model State
    | Import Import.Model Data.LoginData
    | UserSettings UserSettings.Model Data.LoginData State
    | ShowMessage ShowMessage.Model Data.LoginData (Maybe State)
    | PubShowMessage ShowMessage.Model (Maybe State)
    | LoginShowMessage ShowMessage.Model Data.LoginData Url
    | SelectDialog (SS.GDModel Int) State
    | ChangePasswordDialog CP.GDModel State
    | ChangeEmailDialog CE.GDModel State
    | ResetPassword ResetPassword.Model
    | UserListing UserListing.Model Data.LoginData
    | UserEdit UserEdit.Model Data.LoginData
    | DisplayMessage DisplayMessage.GDModel State
    | MessageNLink MessageNLink.GDModel State
    | Wait State (Model -> Msg -> ( Model, Cmd Msg ))


type alias Flags =
    { seed : Int
    , location : String
    , useragent : String
    , debugstring : String
    , width : Int
    , height : Int
    , errorid : Maybe Int
    , login : Maybe JD.Value
    , adminsettings : Maybe JD.Value
    }


type alias SavedRoute =
    { route : Route
    , save : Bool
    }


type alias StylePalette =
    { defaultSpacing : Int
    }


type alias Model =
    { state : State
    , size : Util.Size
    , location : String
    , navkey : Browser.Navigation.Key
    , seed : Seed
    , timezone : Time.Zone
    , savedRoute : SavedRoute
    , prevSearches : List (List S.TagSearch)
    , recentNotes : List Data.ZkListNote
    , errorNotes : Dict String String
    , fontsize : Int
    , stylePalette : StylePalette
    , adminSettings : OD.AdminSettings
    }


type alias PreInitModel =
    { flags : Flags
    , url : Url
    , key : Browser.Navigation.Key
    , mbzone : Maybe Time.Zone
    , mbfontsize : Maybe Int
    }


type PiModel
    = Ready Model
    | PreInit PreInitModel


initLoginState : Model -> State
initLoginState model =
    Login (Login.initialModel Nothing model.adminSettings "zknotes" model.seed)


urlRequest : Browser.UrlRequest -> Msg
urlRequest ur =
    case ur of
        Browser.Internal url ->
            InternalUrl url

        Browser.External str ->
            LoadUrl str


routeState : Model -> Route -> ( State, Cmd Msg )
routeState model route =
    case route of
        LoginR ->
            ( initLoginState model, Cmd.none )

        PublicZkNote id ->
            case stateLogin model.state of
                Just login ->
                    ( ShowMessage
                        { message = "loading article"
                        }
                        login
                        (Just model.state)
                    , case model.state of
                        EView _ _ ->
                            -- if we're in "EView" then do this request to stay in EView.
                            PI.getPublicZkNote model.location (PI.encodeSendMsg (PI.GetZkNote id)) PublicReplyData

                        _ ->
                            sendZIMsg model.location (ZI.GetZkNoteEdit { zknote = id })
                    )

                Nothing ->
                    ( PubShowMessage
                        { message = "loading article"
                        }
                        (Just model.state)
                    , PI.getPublicZkNote model.location (PI.encodeSendMsg (PI.GetZkNote id)) PublicReplyData
                    )

        PublicZkPubId pubid ->
            ( case stateLogin model.state of
                Just login ->
                    ShowMessage
                        { message = "loading article"
                        }
                        login
                        (Just model.state)

                Nothing ->
                    PubShowMessage
                        { message = "loading article"
                        }
                        (Just model.state)
            , PI.getPublicZkNote model.location (PI.encodeSendMsg (PI.GetZkNotePubId pubid)) PublicReplyData
            )

        EditZkNoteR id ->
            case model.state of
                EditZkNote st login ->
                    ( EditZkNote st login
                    , sendZIMsg model.location (ZI.GetZkNoteEdit { zknote = id })
                    )

                EditZkNoteListing st login ->
                    ( EditZkNoteListing st login
                    , sendZIMsg model.location (ZI.GetZkNoteEdit { zknote = id })
                    )

                EView st login ->
                    ( EView st login
                    , PI.getPublicZkNote model.location (PI.encodeSendMsg (PI.GetZkNote id)) PublicReplyData
                    )

                st ->
                    case stateLogin st of
                        Just login ->
                            ( ShowMessage { message = "loading note..." }
                                login
                                (Just model.state)
                            , Cmd.batch
                                [ sendZIMsg
                                    model.location
                                    (ZI.SearchZkNotes <| prevSearchQuery login)
                                , sendZIMsg model.location (ZI.GetZkNoteEdit { zknote = id })
                                ]
                            )

                        Nothing ->
                            ( PubShowMessage { message = "loading note..." }
                                (Just model.state)
                            , PI.getPublicZkNote model.location (PI.encodeSendMsg (PI.GetZkNote id)) PublicReplyData
                            )

        EditZkNoteNew ->
            case model.state of
                EditZkNote st login ->
                    -- handleEditZkNoteCmd should return state probably, or this function should return model.
                    let
                        ( nm, cmd ) =
                            handleEditZkNoteCmd model login (EditZkNote.newWithSave st)
                    in
                    ( nm.state, cmd )

                EditZkNoteListing st login ->
                    ( EditZkNote (EditZkNote.initNew login st.notes st.spmodel []) login, Cmd.none )

                st ->
                    case stateLogin st of
                        Just login ->
                            ( EditZkNote
                                (EditZkNote.initNew login
                                    { notes = []
                                    , offset = 0
                                    , what = ""
                                    }
                                    SP.initModel
                                    []
                                )
                                login
                            , Cmd.none
                            )

                        Nothing ->
                            -- err 'you're not logged in.'
                            ( (displayMessageDialog { model | state = initLoginState model } "can't create a new note; you're not logged in!").state, Cmd.none )

        ResetPasswordR username key ->
            ( ResetPassword <| ResetPassword.initialModel username key "zknotes", Cmd.none )

        SettingsR ->
            case stateLogin model.state of
                Just login ->
                    ( UserSettings (UserSettings.init login model.fontsize) login model.state, Cmd.none )

                Nothing ->
                    ( (displayMessageDialog { model | state = initLoginState model } "can't view user settings; you're not logged in!").state, Cmd.none )

        Top ->
            if (stateRoute model.state).route == Top then
                ( model.state, Cmd.none )

            else
                -- home page if any, or login page if not logged in.
                let
                    ( m, c ) =
                        initialPage model
                in
                ( m.state, c )


stateRoute : State -> SavedRoute
stateRoute state =
    case state of
        View vst ->
            case vst.pubid of
                Just pubid ->
                    { route = PublicZkPubId pubid
                    , save = True
                    }

                Nothing ->
                    case vst.id of
                        Just id ->
                            { route = PublicZkNote id
                            , save = True
                            }

                        Nothing ->
                            { route = Top
                            , save = False
                            }

        EView vst _ ->
            case vst.pubid of
                Just pubid ->
                    { route = PublicZkPubId pubid
                    , save = True
                    }

                Nothing ->
                    case vst.id of
                        Just id ->
                            { route = PublicZkNote id
                            , save = True
                            }

                        Nothing ->
                            { route = Top
                            , save = False
                            }

        EditZkNote st login ->
            st.id
                |> Maybe.map (\id -> { route = EditZkNoteR id, save = True })
                |> Maybe.withDefault { route = EditZkNoteNew, save = False }

        Login _ ->
            { route = LoginR
            , save = False
            }

        UserSettings _ _ _ ->
            { route = SettingsR
            , save = True
            }

        _ ->
            { route = Top
            , save = False
            }


showMessage : Msg -> String
showMessage msg =
    case msg of
        LoginMsg _ ->
            "LoginMsg"

        DisplayMessageMsg _ ->
            "DisplayMessage"

        MessageNLinkMsg _ ->
            "MessageNLink"

        ViewMsg _ ->
            "ViewMsg"

        EditZkNoteMsg _ ->
            "EditZkNoteMsg"

        EditZkNoteListingMsg _ ->
            "EditZkNoteListingMsg"

        UserSettingsMsg _ ->
            "UserSettingsMsg"

        ImportMsg _ ->
            "ImportMsg"

        ShowMessageMsg _ ->
            "ShowMessageMsg"

        UserReplyData urd ->
            "UserReplyData: "
                ++ (Result.map UI.showServerResponse urd
                        |> Result.mapError Util.httpErrorString
                        |> (\r ->
                                case r of
                                    Ok m ->
                                        "message: " ++ m

                                    Err e ->
                                        "error: " ++ e
                           )
                   )

        AdminReplyData urd ->
            "AdminReplyData: "
                ++ (Result.map AI.showServerResponse urd
                        |> Result.mapError Util.httpErrorString
                        |> (\r ->
                                case r of
                                    Ok m ->
                                        "message: " ++ m

                                    Err e ->
                                        "error: " ++ e
                           )
                   )

        ZkReplyData urd ->
            "ZkReplyData: "
                ++ (Result.map ZI.showServerResponse urd
                        |> Result.mapError Util.httpErrorString
                        |> (\r ->
                                case r of
                                    Ok m ->
                                        "message: " ++ m

                                    Err e ->
                                        "error: " ++ e
                           )
                   )

        TAReplyData _ urd ->
            "TAReplyData: "
                ++ (Result.map ZI.showServerResponse urd
                        |> Result.mapError Util.httpErrorString
                        |> (\r ->
                                case r of
                                    Ok m ->
                                        "message: " ++ m

                                    Err e ->
                                        "error: " ++ e
                           )
                   )

        PublicReplyData _ ->
            "PublicReplyData"

        ErrorIndexNote _ ->
            "ErrorIndexNote"

        LoadUrl _ ->
            "LoadUrl"

        InternalUrl _ ->
            "InternalUrl"

        TASelection _ ->
            "TASelection"

        UrlChanged _ ->
            "UrlChanged"

        WindowSize _ ->
            "WindowSize"

        Noop ->
            "Noop"

        WkMsg _ ->
            "WkMsg"

        ReceiveLocalVal _ ->
            "ReceiveLocalVal"

        SelectDialogMsg _ ->
            "SelectDialogMsg"

        ChangePasswordDialogMsg _ ->
            "ChangePasswordDialogMsg"

        ChangeEmailDialogMsg _ ->
            "ChangeEmailDialogMsg"

        ResetPasswordMsg _ ->
            "ResetPasswordMsg"

        Zone _ ->
            "Zone"

        UserListingMsg _ ->
            "UserListingMsg"

        UserEditMsg _ ->
            "UserEditMsg"


showState : State -> String
showState state =
    case state of
        Login _ ->
            "Login"

        EditZkNote _ _ ->
            "EditZkNote"

        EditZkNoteListing _ _ ->
            "EditZkNoteListing"

        View _ ->
            "View"

        EView _ _ ->
            "EView"

        UserSettings _ _ _ ->
            "UserSettings"

        Import _ _ ->
            "Import"

        DisplayMessage _ _ ->
            "DisplayMessage"

        MessageNLink _ _ ->
            "MessageNLink"

        ShowMessage _ _ _ ->
            "ShowMessage"

        PubShowMessage _ _ ->
            "PubShowMessage"

        LoginShowMessage _ _ _ ->
            "LoginShowMessage"

        Wait _ _ ->
            "Wait"

        SelectDialog _ _ ->
            "SelectDialog"

        ChangePasswordDialog _ _ ->
            "ChangePasswordDialog"

        ChangeEmailDialog _ _ ->
            "ChangeEmailDialog"

        ResetPassword _ ->
            "ResetPassword"

        UserListing _ _ ->
            "UserListing"

        UserEdit _ _ ->
            "UserEdit"


unexpectedMsg : Model -> Msg -> Model
unexpectedMsg model msg =
    unexpectedMessage model (showMessage msg)


unexpectedMessage : Model -> String -> Model
unexpectedMessage model msg =
    displayMessageDialog model
        ("unexpected message - " ++ msg ++ "; state was " ++ showState model.state)


viewState : Util.Size -> State -> Model -> Element Msg
viewState size state model =
    case state of
        Login lem ->
            E.map LoginMsg <| Login.view model.stylePalette size lem

        EditZkNote em _ ->
            E.map EditZkNoteMsg <| EditZkNote.view model.timezone size model.recentNotes em

        EditZkNoteListing em ld ->
            E.map EditZkNoteListingMsg <| EditZkNoteListing.view ld size em

        ShowMessage em _ _ ->
            E.map ShowMessageMsg <| ShowMessage.view em

        PubShowMessage em _ ->
            E.map ShowMessageMsg <| ShowMessage.view em

        LoginShowMessage em _ _ ->
            E.map ShowMessageMsg <| ShowMessage.view em

        Import em _ ->
            E.map ImportMsg <| Import.view size em

        View em ->
            E.map ViewMsg <| View.view model.timezone size.width em False

        EView em _ ->
            E.map ViewMsg <| View.view model.timezone size.width em True

        UserSettings em _ _ ->
            E.map UserSettingsMsg <| UserSettings.view em

        DisplayMessage em _ ->
            -- render is at the layout level, not here.
            E.none

        MessageNLink em _ ->
            -- render is at the layout level, not here.
            E.none

        -- E.map DisplayMessageMsg <| DisplayMessage.view em
        Wait innerState _ ->
            E.map (\_ -> Noop) (viewState size innerState model)

        SelectDialog _ _ ->
            -- render is at the layout level, not here.
            E.none

        ChangePasswordDialog _ _ ->
            -- render is at the layout level, not here.
            E.none

        ChangeEmailDialog _ _ ->
            -- render is at the layout level, not here.
            E.none

        ResetPassword st ->
            E.map ResetPasswordMsg (ResetPassword.view size st)

        UserListing st login ->
            E.map UserListingMsg (UserListing.view Common.buttonStyle st)

        UserEdit st login ->
            E.map UserEditMsg (UserEdit.view Common.buttonStyle st)


stateSearch : State -> Maybe ( SP.Model, Data.ZkListNoteSearchResult )
stateSearch state =
    case state of
        Login _ ->
            Nothing

        EditZkNote emod _ ->
            Just ( emod.spmodel, emod.zknSearchResult )

        EditZkNoteListing emod _ ->
            Just ( emod.spmodel, emod.notes )

        ShowMessage _ _ (Just st) ->
            stateSearch st

        ShowMessage _ _ Nothing ->
            Nothing

        PubShowMessage _ (Just st) ->
            stateSearch st

        PubShowMessage _ Nothing ->
            Nothing

        View _ ->
            Nothing

        EView _ st ->
            stateSearch st

        Import _ _ ->
            Nothing

        UserSettings _ _ st ->
            stateSearch st

        LoginShowMessage _ _ _ ->
            Nothing

        SelectDialog _ st ->
            stateSearch st

        ChangePasswordDialog _ st ->
            stateSearch st

        ChangeEmailDialog _ st ->
            stateSearch st

        ResetPassword _ ->
            Nothing

        DisplayMessage _ st ->
            stateSearch st

        MessageNLink _ st ->
            stateSearch st

        Wait st _ ->
            stateSearch st

        UserListing _ _ ->
            Nothing

        UserEdit _ _ ->
            Nothing


stateLogin : State -> Maybe Data.LoginData
stateLogin state =
    case state of
        Login _ ->
            Nothing

        EditZkNote _ login ->
            Just login

        EditZkNoteListing _ login ->
            Just login

        Import _ login ->
            Just login

        View _ ->
            Nothing

        EView _ evstate ->
            stateLogin evstate

        UserSettings _ login _ ->
            Just login

        DisplayMessage _ bestate ->
            stateLogin bestate

        MessageNLink _ bestate ->
            stateLogin bestate

        ShowMessage _ login _ ->
            Just login

        PubShowMessage _ _ ->
            Nothing

        LoginShowMessage _ _ _ ->
            Nothing

        Wait wstate _ ->
            stateLogin wstate

        SelectDialog _ instate ->
            stateLogin instate

        ChangePasswordDialog _ instate ->
            stateLogin instate

        ChangeEmailDialog _ instate ->
            stateLogin instate

        ResetPassword _ ->
            Nothing

        UserListing _ login ->
            Just login

        UserEdit _ login ->
            Just login


sendUIMsg : String -> UI.SendMsg -> Cmd Msg
sendUIMsg location msg =
    sendUIMsgExp location msg UserReplyData


sendUIMsgExp : String -> UI.SendMsg -> (Result Http.Error UI.ServerResponse -> Msg) -> Cmd Msg
sendUIMsgExp location msg tomsg =
    Http.post
        { url = location ++ "/user"
        , body = Http.jsonBody (UI.encodeSendMsg msg)
        , expect = Http.expectJson tomsg UI.serverResponseDecoder
        }


sendAIMsg : String -> AI.SendMsg -> Cmd Msg
sendAIMsg location msg =
    let
        _ =
            Debug.log "sendaimsg" msg
    in
    sendAIMsgExp location msg AdminReplyData


sendAIMsgExp : String -> AI.SendMsg -> (Result Http.Error AI.ServerResponse -> Msg) -> Cmd Msg
sendAIMsgExp location msg tomsg =
    Http.post
        { url = location ++ "/admin"
        , body = Http.jsonBody (AI.encodeSendMsg msg)
        , expect = Http.expectJson tomsg AI.serverResponseDecoder
        }


sendZIMsg : String -> ZI.SendMsg -> Cmd Msg
sendZIMsg location msg =
    sendZIMsgExp location msg ZkReplyData


sendZIMsgExp : String -> ZI.SendMsg -> (Result Http.Error ZI.ServerResponse -> Msg) -> Cmd Msg
sendZIMsgExp location msg tomsg =
    Http.post
        { url = location ++ "/private"
        , body = Http.jsonBody (ZI.encodeSendMsg msg)
        , expect = Http.expectJson tomsg ZI.serverResponseDecoder
        }


{-| send search AND save search in db as a zknote
-}
sendSearch : Model -> S.ZkNoteSearch -> ( Model, Cmd Msg )
sendSearch model search =
    case stateLogin model.state of
        Just ldata ->
            let
                searchnote =
                    { note =
                        { id = Nothing
                        , pubid = Nothing
                        , title = S.printTagSearch (S.getTagSearch search)
                        , content = S.encodeTsl search.tagSearch |> JE.encode 2
                        , editable = False
                        , showtitle = True
                        }
                    , links =
                        [ { otherid = ldata.searchid
                          , direction = Data.To
                          , user = ldata.userid
                          , zknote = Nothing
                          , delete = Nothing
                          }
                        ]
                    }
            in
            -- if this is the same search as last time, don't save.
            if
                (List.head model.prevSearches == Just search.tagSearch)
                    || (search.tagSearch == [ S.SearchTerm [] "" ])
            then
                ( model
                , sendZIMsg model.location (ZI.SearchZkNotes search)
                )

            else
                ( { model | prevSearches = search.tagSearch :: model.prevSearches }
                , Cmd.batch
                    [ sendZIMsg model.location (ZI.SearchZkNotes search)
                    , sendZIMsgExp model.location
                        (ZI.SaveZkNotePlusLinks searchnote)
                        -- ignore the reply!  otherwise if you search while
                        -- creating a new note, that new note gets the search note
                        -- id.
                        (\_ -> Noop)
                    ]
                )

        Nothing ->
            ( model
            , Cmd.none
            )


sendPIMsg : String -> PI.SendMsg -> Cmd Msg
sendPIMsg location msg =
    Http.post
        { url = location ++ "/public"
        , body = Http.jsonBody (PI.encodeSendMsg msg)
        , expect = Http.expectJson PublicReplyData PI.serverResponseDecoder
        }


getListing : Model -> Data.LoginData -> ( Model, Cmd Msg )
getListing model login =
    sendSearch
        { model
            | state =
                ShowMessage
                    { message = "loading articles"
                    }
                    login
                    (Just model.state)
            , seed =
                case model.state of
                    -- save the seed if we're leaving login state.
                    Login lmod ->
                        lmod.seed

                    _ ->
                        model.seed
        }
        S.defaultSearch


addRecentZkListNote : List Data.ZkListNote -> Data.ZkListNote -> List Data.ZkListNote
addRecentZkListNote recent zkln =
    List.take 50 <|
        zkln
            :: List.filter (\x -> x.id /= zkln.id) recent


piview : PiModel -> { title : String, body : List (Html Msg) }
piview pimodel =
    case pimodel of
        Ready model ->
            view model

        PreInit model ->
            { title = "zknotes: initializing"
            , body = []
            }


view : Model -> { title : String, body : List (Html Msg) }
view model =
    { title =
        case model.state of
            EditZkNote ezn _ ->
                ezn.title ++ " - zknote"

            _ ->
                routeTitle model.savedRoute.route
    , body =
        [ case model.state of
            DisplayMessage dm _ ->
                Html.map DisplayMessageMsg <|
                    GD.layout
                        (Just { width = min 600 model.size.width, height = min 500 model.size.height })
                        dm

            MessageNLink dm _ ->
                Html.map MessageNLinkMsg <|
                    GD.layout
                        (Just { width = min 600 model.size.width, height = min 500 model.size.height })
                        dm

            SelectDialog sdm _ ->
                Html.map SelectDialogMsg <|
                    GD.layout
                        (Just { width = min 600 model.size.width, height = min 500 model.size.height })
                        sdm

            ChangePasswordDialog cdm _ ->
                Html.map ChangePasswordDialogMsg <|
                    GD.layout
                        (Just { width = min 600 model.size.width, height = min 200 model.size.height })
                        cdm

            ChangeEmailDialog cdm _ ->
                Html.map ChangeEmailDialogMsg <|
                    GD.layout
                        (Just { width = min 600 model.size.width, height = min 200 model.size.height })
                        cdm

            _ ->
                E.layout [ EF.size model.fontsize, E.width E.fill ] <| viewState model.size model.state model
        ]
    }


piupdate : Msg -> PiModel -> ( PiModel, Cmd Msg )
piupdate msg initmodel =
    case initmodel of
        Ready model ->
            let
                ( m, c ) =
                    urlupdate msg model
            in
            ( Ready m, c )

        PreInit imod ->
            let
                nmod =
                    case msg of
                        Zone zone ->
                            { imod | mbzone = Just zone }

                        ReceiveLocalVal lv ->
                            let
                                default =
                                    16
                            in
                            case lv.name of
                                "fontsize" ->
                                    case lv.value of
                                        Just v ->
                                            case String.toInt v of
                                                Just i ->
                                                    { imod | mbfontsize = Just i }

                                                Nothing ->
                                                    { imod | mbfontsize = Just default }

                                        Nothing ->
                                            { imod | mbfontsize = Just default }

                                _ ->
                                    { imod | mbfontsize = Nothing }

                        _ ->
                            imod
            in
            case ( nmod.mbzone, nmod.mbfontsize ) of
                ( Just zone, Just fontsize ) ->
                    let
                        ( m, c ) =
                            init imod.flags imod.url imod.key zone fontsize
                    in
                    ( Ready m, c )

                _ ->
                    ( PreInit nmod, Cmd.none )


{-| urlUpdate: all URL code shall go here! regular code shall not worry about urls!
this function calls actualupdate where the app stuff happens.
url messages and state based url changes are done here.
-}
urlupdate : Msg -> Model -> ( Model, Cmd Msg )
urlupdate msg model =
    let
        ( nm, cmd ) =
            case msg of
                InternalUrl url ->
                    let
                        ( state, icmd ) =
                            parseUrl url
                                |> Maybe.map (routeState model)
                                |> Maybe.withDefault ( model.state, Cmd.none )

                        bcmd =
                            case model.state of
                                EditZkNote s ld ->
                                    if EditZkNote.dirty s then
                                        Cmd.batch
                                            [ icmd
                                            , sendZIMsg model.location
                                                (ZI.SaveZkNotePlusLinks <| EditZkNote.fullSave s)
                                            ]

                                    else
                                        icmd

                                _ ->
                                    icmd
                    in
                    ( { model | state = state }, bcmd )

                LoadUrl urlstr ->
                    -- load foreign site
                    -- ( model, Browser.Navigation.load urlstr )
                    ( model, Cmd.none )

                UrlChanged url ->
                    -- we get this from forward and back buttons.  if the user changes the url
                    -- in the browser address bar, its a site reload so this isn't called.
                    case parseUrl url of
                        Just route ->
                            if route == (stateRoute model.state).route then
                                ( model, Cmd.none )

                            else
                                let
                                    ( st, rscmd ) =
                                        routeState model route
                                in
                                -- swap out the savedRoute, so we don't write over history.
                                ( { model
                                    | state = st
                                    , savedRoute =
                                        let
                                            nssr =
                                                stateRoute st
                                        in
                                        { nssr | save = False }
                                  }
                                , rscmd
                                )

                        Nothing ->
                            -- load foreign site
                            -- ( model, Browser.Navigation.load (Url.toString url) )
                            ( model, Cmd.none )

                _ ->
                    -- not an url related message!  pass it on to the 'actualupdate'
                    -- this is where all the app stuff happens.
                    actualupdate msg model

        sr =
            stateRoute nm.state
    in
    -- when the route changes, change the address bar, optionally pushing what's there to
    -- browser history.
    if sr.route /= nm.savedRoute.route then
        ( { nm | savedRoute = sr }
        , if model.savedRoute.save then
            Cmd.batch
                [ cmd
                , Browser.Navigation.pushUrl nm.navkey
                    (routeUrl sr.route)
                ]

          else
            Cmd.batch
                [ cmd
                , Browser.Navigation.replaceUrl nm.navkey
                    (routeUrl sr.route)
                ]
        )

    else
        ( nm, cmd )


shDialog : Model -> Model
shDialog model =
    { model
        | state =
            SelectDialog
                (SS.init
                    { choices = List.indexedMap (\i ps -> ( i, S.printTagSearch (S.andifySearches ps) )) model.prevSearches
                    , selected = Nothing
                    , search = ""
                    }
                    Common.buttonStyle
                    (E.map (\_ -> ()) (viewState model.size model.state model))
                )
                model.state
    }


displayMessageDialog : Model -> String -> Model
displayMessageDialog model message =
    { model
        | state =
            DisplayMessage
                (DisplayMessage.init Common.buttonStyle
                    message
                    (E.map (\_ -> ()) (viewState model.size model.state model))
                )
                model.state
    }


displayMessageNLinkDialog : Model -> String -> String -> String -> Model
displayMessageNLinkDialog model message url text =
    { model
        | state =
            MessageNLink
                (MessageNLink.init Common.buttonStyle
                    message
                    url
                    text
                    (E.map (\_ -> ()) (viewState model.size model.state model))
                )
                model.state
    }


actualupdate : Msg -> Model -> ( Model, Cmd Msg )
actualupdate msg model =
    case ( msg, model.state ) of
        ( _, Wait wst wfn ) ->
            let
                ( nmd, cmd ) =
                    wfn model msg
            in
            ( nmd, cmd )

        ( ReceiveLocalVal lv, _ ) ->
            -- update the font size
            ( model, Cmd.none )

        ( WindowSize s, _ ) ->
            ( { model | size = s }, Cmd.none )

        ( SelectDialogMsg sdmsg, SelectDialog sdmod instate ) ->
            case GD.update sdmsg sdmod of
                GD.Dialog nmod ->
                    ( { model | state = SelectDialog nmod instate }, Cmd.none )

                GD.Ok return ->
                    case List.head (List.drop return model.prevSearches) of
                        Just ts ->
                            let
                                sendsearch =
                                    sendZIMsg model.location
                                        (ZI.SearchZkNotes
                                            { tagSearch = ts
                                            , offset = 0
                                            , limit = Nothing
                                            , what = ""
                                            , list = True
                                            }
                                        )

                                ( ns, cmd ) =
                                    case instate of
                                        EditZkNote ezn login ->
                                            ( EditZkNote (Tuple.first <| EditZkNote.updateSearch ts ezn) login
                                            , sendsearch
                                            )

                                        EditZkNoteListing ezn login ->
                                            ( EditZkNoteListing (Tuple.first <| EditZkNoteListing.updateSearch ts ezn) login
                                            , sendsearch
                                            )

                                        _ ->
                                            ( instate, Cmd.none )
                            in
                            ( { model | state = ns }, cmd )

                        Nothing ->
                            ( { model | state = instate }, Cmd.none )

                GD.Cancel ->
                    ( { model | state = instate }, Cmd.none )

        ( ChangePasswordDialogMsg sdmsg, ChangePasswordDialog sdmod instate ) ->
            case GD.update sdmsg sdmod of
                GD.Dialog nmod ->
                    ( { model | state = ChangePasswordDialog nmod instate }, Cmd.none )

                GD.Ok return ->
                    ( { model | state = instate }
                    , sendUIMsg model.location <| UI.ChangePassword return
                    )

                GD.Cancel ->
                    ( { model | state = instate }, Cmd.none )

        ( ChangeEmailDialogMsg sdmsg, ChangeEmailDialog sdmod instate ) ->
            case GD.update sdmsg sdmod of
                GD.Dialog nmod ->
                    ( { model | state = ChangeEmailDialog nmod instate }, Cmd.none )

                GD.Ok return ->
                    ( { model | state = instate }
                    , sendUIMsg model.location <| UI.ChangeEmail return
                    )

                GD.Cancel ->
                    ( { model | state = instate }, Cmd.none )

        ( ResetPasswordMsg rmsg, ResetPassword rst ) ->
            let
                ( nst, cmd ) =
                    ResetPassword.update rmsg rst
            in
            case cmd of
                ResetPassword.Ok ->
                    ( { model | state = ResetPassword nst }
                    , sendUIMsg model.location
                        (UI.SetPassword { uid = nst.userId, newpwd = nst.password, reset_key = nst.reset_key })
                    )

                ResetPassword.None ->
                    ( { model | state = ResetPassword nst }, Cmd.none )

        ( TASelection jv, state ) ->
            case JD.decodeValue Data.decodeTASelection jv of
                Ok tas ->
                    case state of
                        EditZkNote emod login ->
                            case EditZkNote.onTASelection emod tas of
                                EditZkNote.TAError e ->
                                    ( displayMessageDialog model e, Cmd.none )

                                EditZkNote.TASave s ->
                                    ( model
                                    , sendZIMsgExp model.location
                                        (ZI.SaveZkNotePlusLinks s)
                                        (TAReplyData tas)
                                    )

                                EditZkNote.TAUpdated nemod s ->
                                    ( { model | state = EditZkNote nemod login }
                                    , case s of
                                        Just sel ->
                                            setTASelection (Data.encodeSetSelection sel)

                                        Nothing ->
                                            Cmd.none
                                    )

                                EditZkNote.TANoop ->
                                    ( model, Cmd.none )

                        _ ->
                            ( model, Cmd.none )

                Err e ->
                    ( displayMessageDialog model <| JD.errorToString e, Cmd.none )

        ( UserSettingsMsg umsg, UserSettings umod login prevstate ) ->
            let
                ( numod, c ) =
                    UserSettings.update umsg umod
            in
            case c of
                UserSettings.Done ->
                    ( { model | state = prevstate }, Cmd.none )

                UserSettings.LogOut ->
                    ( { model | state = initLoginState model }
                    , sendUIMsg model.location UI.Logout
                    )

                UserSettings.ChangePassword ->
                    ( { model
                        | state =
                            ChangePasswordDialog (CP.init (OD.toLd login) Common.buttonStyle (UserSettings.view numod |> E.map (always ())))
                                (UserSettings numod login prevstate)
                      }
                    , Cmd.none
                    )

                UserSettings.ChangeEmail ->
                    ( { model
                        | state =
                            ChangeEmailDialog (CE.init (OD.toLd login) Common.buttonStyle (UserSettings.view numod |> E.map (always ())))
                                (UserSettings numod login prevstate)
                      }
                    , Cmd.none
                    )

                UserSettings.ChangeFontSize size ->
                    ( { model
                        | state = UserSettings numod login prevstate
                        , fontsize = size
                      }
                    , LS.storeLocalVal { name = "fontsize", value = String.fromInt size }
                    )

                UserSettings.None ->
                    ( { model | state = UserSettings numod login prevstate }, Cmd.none )

        ( UserListingMsg umsg, UserListing umod login ) ->
            let
                ( numod, c ) =
                    UserListing.update umsg umod
            in
            case c of
                UserListing.Done ->
                    initialPage model

                UserListing.NewUser ->
                    ( { model | state = UserEdit UserEdit.initNew login }, Cmd.none )

                UserListing.EditUser ld ->
                    ( { model | state = UserEdit (UserEdit.init ld) login }, Cmd.none )

                UserListing.None ->
                    ( { model | state = UserListing numod login }, Cmd.none )

        ( UserEditMsg umsg, UserEdit umod login ) ->
            let
                ( numod, c ) =
                    UserEdit.update umsg umod
            in
            case c of
                UserEdit.Done ->
                    ( model
                    , sendAIMsg model.location AI.GetUsers
                    )

                UserEdit.Delete id ->
                    ( model
                    , sendAIMsg model.location <| AI.DeleteUser id
                    )

                UserEdit.Save ld ->
                    ( model
                    , sendAIMsg model.location <| AI.UpdateUser ld
                    )

                UserEdit.None ->
                    ( { model | state = UserEdit numod login }, Cmd.none )

        ( WkMsg rkey, Login ls ) ->
            case rkey of
                Ok key ->
                    handleLogin model (Login.onWkKeyPress key ls)

                Err _ ->
                    ( model, Cmd.none )

        ( LoginMsg lm, Login ls ) ->
            handleLogin model (Login.update lm ls)

        ( PublicReplyData prd, state ) ->
            case prd of
                Err e ->
                    ( displayMessageDialog model <| Util.httpErrorString e
                    , Cmd.none
                    )

                Ok piresponse ->
                    case piresponse of
                        PI.ServerError e ->
                            case Dict.get e model.errorNotes of
                                Just url ->
                                    ( displayMessageNLinkDialog { model | state = initLoginState model } e url "more info"
                                    , Cmd.none
                                    )

                                Nothing ->
                                    ( displayMessageDialog { model | state = initLoginState model } e, Cmd.none )

                        PI.ZkNote fbe ->
                            let
                                vstate =
                                    case stateLogin state of
                                        Just _ ->
                                            EView (View.initFull fbe) state

                                        Nothing ->
                                            View (View.initFull fbe)
                            in
                            ( { model | state = vstate }
                            , Cmd.none
                            )

        ( ErrorIndexNote rsein, state ) ->
            case rsein of
                Err e ->
                    ( displayMessageDialog model <| Util.httpErrorString e
                    , Cmd.none
                    )

                Ok resp ->
                    case resp of
                        PI.ServerError e ->
                            -- if there's an error on getting the error index note, just display it.
                            ( displayMessageDialog model <| e, Cmd.none )

                        PI.ZkNote fbe ->
                            ( { model | errorNotes = MC.linkDict fbe.zknote.content }
                            , Cmd.none
                            )

        ( TAReplyData tas urd, state ) ->
            case urd of
                Err e ->
                    ( displayMessageDialog model <| Util.httpErrorString e, Cmd.none )

                Ok uiresponse ->
                    case uiresponse of
                        ZI.ServerError e ->
                            ( displayMessageDialog model <| e, Cmd.none )

                        ZI.SavedZkNotePlusLinks szkn ->
                            case state of
                                EditZkNote emod login ->
                                    let
                                        ( eznst, cmd ) =
                                            EditZkNote.onLinkBackSaved
                                                emod
                                                (Just tas)
                                                szkn
                                    in
                                    handleEditZkNoteCmd model login ( eznst, cmd )

                                _ ->
                                    -- just ignore if we're not editing a new note.
                                    ( model, Cmd.none )

                        _ ->
                            ( unexpectedMsg model msg, Cmd.none )

        ( UserReplyData urd, state ) ->
            case urd of
                Err e ->
                    ( displayMessageDialog model <| Util.httpErrorString e, Cmd.none )

                Ok uiresponse ->
                    case uiresponse of
                        UI.ServerError e ->
                            ( displayMessageDialog model <| e, Cmd.none )

                        UI.RegistrationSent ->
                            ( model, Cmd.none )

                        UI.LoggedIn oalogin ->
                            case Data.fromOaLd oalogin of
                                Ok login ->
                                    let
                                        getlisting =
                                            sendSearch
                                                { model
                                                    | state =
                                                        ShowMessage
                                                            { message = "loading articles"
                                                            }
                                                            login
                                                            (Just model.state)
                                                    , seed =
                                                        case state of
                                                            -- save the seed if we're leaving login state.
                                                            Login lmod ->
                                                                lmod.seed

                                                            _ ->
                                                                model.seed
                                                }
                                                S.defaultSearch

                                        lgmod =
                                            { model
                                                | state =
                                                    ShowMessage { message = "logged in" }
                                                        login
                                                        Nothing
                                            }
                                    in
                                    case state of
                                        Login lm ->
                                            -- we're logged in!
                                            initialPage lgmod

                                        LoginShowMessage _ li url ->
                                            let
                                                ( m, cmd ) =
                                                    parseUrl url
                                                        |> Maybe.andThen
                                                            (\s ->
                                                                case s of
                                                                    Top ->
                                                                        Nothing

                                                                    _ ->
                                                                        Just s
                                                            )
                                                        |> Maybe.map
                                                            (routeState
                                                                lgmod
                                                            )
                                                        |> Maybe.map (\( st, cm ) -> ( { model | state = st }, cm ))
                                                        |> Maybe.withDefault (initialPage lgmod)
                                            in
                                            ( m, cmd )

                                        _ ->
                                            ( displayMessageDialog model "logged in"
                                            , Cmd.none
                                            )

                                Err e ->
                                    ( displayMessageDialog model (JD.errorToString e)
                                    , Cmd.none
                                    )

                        UI.LoggedOut ->
                            ( model, Cmd.none )

                        UI.ResetPasswordAck ->
                            let
                                nmod =
                                    { model
                                        | state = initLoginState model
                                    }
                            in
                            ( displayMessageDialog nmod "password reset attempted!  if you're a valid user, check your inbox for a reset email."
                            , Cmd.none
                            )

                        UI.SetPasswordAck ->
                            let
                                nmod =
                                    { model
                                        | state = initLoginState model
                                    }
                            in
                            ( displayMessageDialog nmod "password reset complete!"
                            , Cmd.none
                            )

                        UI.ChangedPassword ->
                            ( displayMessageDialog model "password changed"
                            , Cmd.none
                            )

                        UI.ChangedEmail ->
                            ( displayMessageDialog model "email change confirmation sent!  check your inbox (or spam folder) for an email with title 'change zknotes email', and follow the enclosed link to change to the new address."
                            , Cmd.none
                            )

                        UI.UserExists ->
                            case state of
                                Login lmod ->
                                    ( { model | state = Login <| Login.userExists lmod }, Cmd.none )

                                _ ->
                                    ( unexpectedMessage model (UI.showServerResponse uiresponse)
                                    , Cmd.none
                                    )

                        UI.UnregisteredUser ->
                            case state of
                                Login lmod ->
                                    ( { model | state = Login <| Login.unregisteredUser lmod }, Cmd.none )

                                _ ->
                                    ( unexpectedMessage model (UI.showServerResponse uiresponse)
                                    , Cmd.none
                                    )

                        UI.NotLoggedIn ->
                            case state of
                                Login lmod ->
                                    ( { model | state = Login lmod }, Cmd.none )

                                _ ->
                                    ( { model | state = initLoginState model }, Cmd.none )

                        UI.InvalidUserOrPwd ->
                            case state of
                                Login lmod ->
                                    ( { model | state = Login <| Login.invalidUserOrPwd lmod }, Cmd.none )

                                _ ->
                                    ( unexpectedMessage { model | state = initLoginState model }
                                        (UI.showServerResponse uiresponse)
                                    , Cmd.none
                                    )

        ( AdminReplyData ard, state ) ->
            case ard of
                Err e ->
                    ( displayMessageDialog model <| Util.httpErrorString e, Cmd.none )

                Ok airesponse ->
                    case airesponse of
                        AI.NotLoggedIn ->
                            case state of
                                Login lmod ->
                                    ( { model | state = Login lmod }, Cmd.none )

                                _ ->
                                    ( { model | state = initLoginState model }, Cmd.none )

                        AI.Users users ->
                            case stateLogin model.state of
                                Just login ->
                                    ( { model | state = UserListing (UserListing.init users) login }, Cmd.none )

                                Nothing ->
                                    ( displayMessageDialog model "not logged in", Cmd.none )

                        AI.UserDeleted id ->
                            ( displayMessageDialog model "user deleted!"
                            , sendAIMsg model.location AI.GetUsers
                            )

                        AI.UserUpdated ld ->
                            case model.state of
                                UserEdit ue login ->
                                    ( displayMessageDialog { model | state = UserEdit (UserEdit.onUserUpdated ue ld) login } "user updated"
                                    , Cmd.none
                                    )

                                _ ->
                                    ( model, Cmd.none )

                        AI.ServerError e ->
                            ( displayMessageDialog model <| e, Cmd.none )

        ( ZkReplyData zrd, state ) ->
            case zrd of
                Err e ->
                    ( displayMessageDialog model <| Util.httpErrorString e, Cmd.none )

                Ok ziresponse ->
                    case ziresponse of
                        ZI.ServerError e ->
                            ( displayMessageDialog model <| e, Cmd.none )

                        ZI.PowerDeleteComplete count ->
                            case model.state of
                                EditZkNoteListing mod li ->
                                    ( { model | state = EditZkNoteListing (EditZkNoteListing.onPowerDeleteComplete count li mod) li }, Cmd.none )

                                _ ->
                                    ( model, Cmd.none )

                        ZI.ZkNoteSearchResult sr ->
                            if sr.what == "prevSearches" then
                                let
                                    pses =
                                        List.filterMap
                                            (\zknote ->
                                                JD.decodeString S.decodeTsl zknote.content
                                                    |> Result.toMaybe
                                            )
                                            sr.notes

                                    laststack =
                                        pses
                                            |> List.head
                                            |> Maybe.withDefault []
                                            |> List.reverse
                                            |> List.drop 1
                                            |> List.reverse
                                in
                                ( { model
                                    | prevSearches = pses
                                    , state =
                                        case model.state of
                                            EditZkNoteListing znlstate login_ ->
                                                EditZkNoteListing (EditZkNoteListing.updateSearchStack laststack znlstate) login_

                                            EditZkNote znstate login_ ->
                                                EditZkNote (EditZkNote.updateSearchStack laststack znstate) login_

                                            _ ->
                                                model.state
                                  }
                                , Cmd.none
                                )

                            else
                                ( model, Cmd.none )

                        ZI.ZkListNoteSearchResult sr ->
                            case state of
                                EditZkNoteListing znlstate login_ ->
                                    ( { model | state = EditZkNoteListing (EditZkNoteListing.updateSearchResult sr znlstate) login_ }
                                    , Cmd.none
                                    )

                                EditZkNote znstate login_ ->
                                    ( { model | state = EditZkNote (EditZkNote.updateSearchResult sr znstate) login_ }
                                    , Cmd.none
                                    )

                                Import istate login_ ->
                                    ( { model | state = Import (Import.updateSearchResult sr istate) login_ }
                                    , Cmd.none
                                    )

                                ShowMessage _ login _ ->
                                    ( { model | state = EditZkNoteListing { notes = sr, spmodel = SP.initModel, dialog = Nothing } login }
                                    , Cmd.none
                                    )

                                _ ->
                                    ( unexpectedMessage model (ZI.showServerResponse ziresponse)
                                    , Cmd.none
                                    )

                        ZI.ZkNote zkn ->
                            case state of
                                EditZkNote ezn login ->
                                    handleEditZkNoteCmd model login (EditZkNote.onZkNote zkn ezn)

                                _ ->
                                    ( unexpectedMessage model (ZI.showServerResponse ziresponse)
                                    , Cmd.none
                                    )

                        ZI.ZkNoteEdit zne ->
                            case stateLogin state of
                                Just login ->
                                    let
                                        ( spmod, sres ) =
                                            stateSearch state
                                                |> Maybe.withDefault ( SP.initModel, { notes = [], offset = 0, what = "" } )

                                        ( nst, c ) =
                                            EditZkNote.initFull login
                                                sres
                                                zne.zknote
                                                zne.links
                                                spmod

                                        s =
                                            case state of
                                                EditZkNote eznst _ ->
                                                    EditZkNote.copyTabs eznst nst
                                                        |> EditZkNote.tabsOnLoad

                                                _ ->
                                                    nst
                                    in
                                    ( { model
                                        | state =
                                            EditZkNote
                                                s
                                                login
                                        , recentNotes =
                                            addRecentZkListNote model.recentNotes
                                                { id = zne.zknote.id
                                                , user = zne.zknote.user
                                                , title = zne.zknote.title
                                                , createdate = zne.zknote.createdate
                                                , changeddate = zne.zknote.changeddate
                                                , sysids = zne.zknote.sysids
                                                }
                                      }
                                    , sendZIMsg model.location <| ZI.GetZkNoteComments c
                                    )

                                _ ->
                                    ( unexpectedMessage model (ZI.showServerResponse ziresponse)
                                    , Cmd.none
                                    )

                        ZI.ZkNoteComments zc ->
                            case state of
                                EditZkNote s login ->
                                    ( { model | state = EditZkNote (EditZkNote.commentsRecieved zc s) login }
                                    , Cmd.none
                                    )

                                _ ->
                                    ( unexpectedMessage model (ZI.showServerResponse ziresponse)
                                    , Cmd.none
                                    )

                        ZI.SavedZkNote szkn ->
                            case state of
                                EditZkNote emod login ->
                                    let
                                        eznst =
                                            EditZkNote.onSaved
                                                emod
                                                szkn

                                        rn =
                                            EditZkNote.toZkListNote eznst
                                                |> Maybe.map
                                                    (\zkln ->
                                                        addRecentZkListNote model.recentNotes zkln
                                                    )
                                                |> Maybe.withDefault model.recentNotes

                                        st =
                                            EditZkNote eznst login
                                    in
                                    ( { model | state = st, recentNotes = rn }
                                    , Cmd.none
                                    )

                                _ ->
                                    -- just ignore if we're not editing a new note.
                                    ( model, Cmd.none )

                        ZI.SavedZkNotePlusLinks szkn ->
                            case state of
                                EditZkNote emod login ->
                                    let
                                        eznst =
                                            EditZkNote.onSaved
                                                emod
                                                szkn

                                        rn =
                                            EditZkNote.toZkListNote eznst
                                                |> Maybe.map
                                                    (\zkln ->
                                                        addRecentZkListNote model.recentNotes zkln
                                                    )
                                                |> Maybe.withDefault model.recentNotes

                                        st =
                                            EditZkNote eznst login
                                    in
                                    ( { model | state = st, recentNotes = rn }
                                    , Cmd.none
                                    )

                                _ ->
                                    -- just ignore if we're not editing a new note.
                                    ( model, Cmd.none )

                        ZI.DeletedZkNote beid ->
                            ( model, Cmd.none )

                        ZI.SavedZkLinks ->
                            ( model, Cmd.none )

                        ZI.ZkLinks zkl ->
                            ( model, Cmd.none )

                        ZI.SavedImportZkNotes ->
                            ( model, Cmd.none )

                        ZI.HomeNoteSet id ->
                            case model.state of
                                EditZkNote eznstate login ->
                                    let
                                        x =
                                            EditZkNote.setHomeNote eznstate id
                                    in
                                    ( { model
                                        | state =
                                            EditZkNote x { login | homenote = Just id }
                                      }
                                    , Cmd.none
                                    )

                                _ ->
                                    ( model, Cmd.none )

        ( ViewMsg em, View es ) ->
            let
                ( emod, ecmd ) =
                    View.update em es
            in
            case ecmd of
                View.None ->
                    ( { model | state = View emod }, Cmd.none )

                View.Done ->
                    ( { model | state = View emod }, Cmd.none )

                View.Switch id ->
                    ( { model
                        | state =
                            PubShowMessage
                                { message = "loading article"
                                }
                                (Just model.state)
                      }
                    , sendPIMsg model.location
                        (PI.GetZkNote id)
                    )

        ( ViewMsg em, EView es state ) ->
            let
                ( emod, ecmd ) =
                    View.update em es
            in
            case ecmd of
                View.None ->
                    ( { model | state = EView emod state }, Cmd.none )

                View.Done ->
                    case state of
                        EditZkNote _ _ ->
                            -- revert to the edit state.
                            ( { model | state = state }, Cmd.none )

                        _ ->
                            case es.id of
                                Just id ->
                                    ( { model | state = state }
                                    , sendZIMsg model.location (ZI.GetZkNoteEdit { zknote = id })
                                    )

                                Nothing ->
                                    -- uh, initial page I guess.  would expect prev state to be edit if no id.
                                    initialPage model

                View.Switch id ->
                    ( model
                      -- , sendUIMsg model.location (UI.GetZkNoteEdit { zknote = id })
                    , sendPIMsg model.location (PI.GetZkNote id)
                    )

        ( EditZkNoteMsg em, EditZkNote es login ) ->
            handleEditZkNoteCmd model login (EditZkNote.update em es)

        ( WkMsg reskey, EditZkNote es login ) ->
            case reskey of
                Ok key ->
                    handleEditZkNoteCmd model login (EditZkNote.onWkKeyPress key es)

                Err e ->
                    ( model, Cmd.none )

        ( WkMsg reskey, EditZkNoteListing es login ) ->
            case reskey of
                Ok key ->
                    handleEditZkNoteListing model
                        login
                        (EditZkNoteListing.onWkKeyPress key es)

                Err e ->
                    ( model, Cmd.none )

        ( EditZkNoteListingMsg em, EditZkNoteListing es login ) ->
            handleEditZkNoteListing model login (EditZkNoteListing.update em es login)

        ( ImportMsg em, Import es login ) ->
            let
                ( emod, ecmd ) =
                    Import.update em es

                backtolisting =
                    \imod ->
                        let
                            nm =
                                { model
                                    | state =
                                        EditZkNoteListing
                                            { notes = imod.zknSearchResult
                                            , spmodel = imod.spmodel
                                            , dialog = Nothing
                                            }
                                            login
                                }
                        in
                        case SP.getSearch imod.spmodel of
                            Just s ->
                                sendSearch nm s

                            Nothing ->
                                ( nm, Cmd.none )
            in
            case ecmd of
                Import.None ->
                    ( { model | state = Import emod login }, Cmd.none )

                Import.SaveExit notes ->
                    let
                        ( m, c ) =
                            backtolisting emod

                        notecmds =
                            List.map
                                (\n ->
                                    sendZIMsg model.location
                                        (ZI.SaveImportZkNotes [ n ])
                                )
                                notes
                    in
                    ( m
                    , Cmd.batch
                        (c
                            :: notecmds
                        )
                    )

                Import.Search s ->
                    sendSearch { model | state = Import emod login } s

                Import.SelectFiles ->
                    ( { model | state = Import emod login }
                    , FS.files []
                        (\a b -> ImportMsg (Import.FilesSelected a b))
                    )

                Import.Cancel ->
                    backtolisting emod

                Import.Command cmd ->
                    ( model, Cmd.map ImportMsg cmd )

        ( DisplayMessageMsg bm, DisplayMessage bs prevstate ) ->
            case GD.update bm bs of
                GD.Dialog nmod ->
                    ( { model | state = DisplayMessage nmod prevstate }, Cmd.none )

                GD.Ok return ->
                    case prevstate of
                        ShowMessage _ _ (Just ps) ->
                            ( { model | state = ps }, Cmd.none )

                        PubShowMessage _ (Just ps) ->
                            ( { model | state = ps }, Cmd.none )

                        _ ->
                            ( { model | state = prevstate }, Cmd.none )

                GD.Cancel ->
                    ( { model | state = prevstate }, Cmd.none )

        ( MessageNLinkMsg bm, MessageNLink bs prevstate ) ->
            case GD.update bm bs of
                GD.Dialog nmod ->
                    ( { model | state = MessageNLink nmod prevstate }, Cmd.none )

                GD.Ok return ->
                    case prevstate of
                        ShowMessage _ _ (Just ps) ->
                            ( { model | state = ps }, Cmd.none )

                        PubShowMessage _ (Just ps) ->
                            ( { model | state = ps }, Cmd.none )

                        _ ->
                            ( { model | state = prevstate }, Cmd.none )

                GD.Cancel ->
                    ( { model | state = prevstate }, Cmd.none )

        ( MessageNLinkMsg GD.Noop, _ ) ->
            ( model, Cmd.none )

        ( Noop, _ ) ->
            ( model, Cmd.none )

        ( ChangePasswordDialogMsg GD.Noop, _ ) ->
            ( model, Cmd.none )

        ( ChangeEmailDialogMsg GD.Noop, _ ) ->
            ( model, Cmd.none )

        ( SelectDialogMsg GD.Noop, _ ) ->
            ( model, Cmd.none )

        ( DisplayMessageMsg GD.Noop, _ ) ->
            ( model, Cmd.none )

        ( x, y ) ->
            ( unexpectedMsg model x
            , Cmd.none
            )


handleEditZkNoteCmd model login ( emod, ecmd ) =
    let
        backtolisting =
            let
                nm =
                    { model
                        | state =
                            EditZkNoteListing
                                { notes = emod.zknSearchResult
                                , spmodel = emod.spmodel
                                , dialog = Nothing
                                }
                                login
                    }
            in
            case SP.getSearch emod.spmodel of
                Just s ->
                    sendSearch nm s

                Nothing ->
                    ( nm, Cmd.none )
    in
    case ecmd of
        EditZkNote.SaveExit snpl ->
            let
                gotres =
                    let
                        nm =
                            { model
                                | state =
                                    EditZkNoteListing
                                        { notes = emod.zknSearchResult
                                        , spmodel = emod.spmodel
                                        , dialog = Nothing
                                        }
                                        login
                            }
                    in
                    case SP.getSearch emod.spmodel of
                        Just s ->
                            sendSearch nm s

                        Nothing ->
                            ( nm, Cmd.none )

                onmsg : Model -> Msg -> ( Model, Cmd Msg )
                onmsg st ms =
                    case ms of
                        ZkReplyData (Ok (ZI.SavedZkNotePlusLinks szn)) ->
                            gotres

                        ZkReplyData (Ok (ZI.ServerError e)) ->
                            ( displayMessageDialog model e
                            , Cmd.none
                            )

                        _ ->
                            ( unexpectedMsg model ms
                            , Cmd.none
                            )
            in
            ( { model
                | state =
                    Wait
                        (ShowMessage
                            { message = "loading articles"
                            }
                            login
                            (Just model.state)
                        )
                        onmsg
              }
            , sendZIMsg model.location
                (ZI.SaveZkNotePlusLinks snpl)
            )

        EditZkNote.Save snpl ->
            ( { model | state = EditZkNote emod login }
            , sendZIMsg model.location
                (ZI.SaveZkNotePlusLinks snpl)
            )

        EditZkNote.None ->
            ( { model | state = EditZkNote emod login }, Cmd.none )

        EditZkNote.Revert ->
            backtolisting

        EditZkNote.Delete id ->
            -- issue delete and go back to listing.
            let
                ( m, c ) =
                    backtolisting
            in
            ( { m
                | state =
                    Wait m.state
                        (\mod _ ->
                            -- stop waiting, issue listing query when a message
                            -- is received. (presumably delete reply)
                            ( { mod | state = m.state }, c )
                        )
              }
            , sendZIMsg model.location
                (ZI.DeleteZkNote id)
            )

        EditZkNote.Switch id ->
            let
                ( st, cmd ) =
                    ( ShowMessage { message = "loading note..." }
                        login
                        (Just model.state)
                    , sendZIMsg model.location (ZI.GetZkNoteEdit { zknote = id })
                    )
            in
            ( { model | state = st }, cmd )

        EditZkNote.SaveSwitch s id ->
            let
                ( st, cmd ) =
                    ( ShowMessage { message = "loading note..." }
                        login
                        (Just model.state)
                    , sendZIMsg model.location (ZI.GetZkNoteEdit { zknote = id })
                    )
            in
            ( { model | state = st }
            , Cmd.batch
                [ cmd
                , sendZIMsg model.location
                    (ZI.SaveZkNotePlusLinks s)
                ]
            )

        EditZkNote.View v ->
            ( { model
                | state =
                    EView
                        (View.initSzn
                            v.note
                            v.createdate
                            v.changeddate
                            v.links
                            v.panelnote
                        )
                        (EditZkNote emod login)
              }
            , Cmd.none
            )

        EditZkNote.GetTASelection id what ->
            ( { model | state = EditZkNote emod login }
            , getTASelection (JE.object [ ( "id", JE.string id ), ( "what", JE.string what ) ])
            )

        EditZkNote.Search s ->
            sendSearch { model | state = EditZkNote emod login } s

        EditZkNote.SearchHistory ->
            ( shDialog model
            , Cmd.none
            )

        EditZkNote.BigSearch ->
            backtolisting

        EditZkNote.Settings ->
            ( { model | state = UserSettings (UserSettings.init login model.fontsize) login (EditZkNote emod login) }
            , Cmd.none
            )

        EditZkNote.Admin ->
            ( model
            , sendAIMsg model.location AI.GetUsers
            )

        EditZkNote.GetZkNote id ->
            ( { model | state = EditZkNote emod login }
            , sendZIMsg model.location (ZI.GetZkNote id)
            )

        EditZkNote.SetHomeNote id ->
            ( { model | state = EditZkNote emod login }
            , sendZIMsg model.location (ZI.SetHomeNote id)
            )

        EditZkNote.AddToRecent zkln ->
            ( { model
                | state = EditZkNote emod login
                , recentNotes = addRecentZkListNote model.recentNotes zkln
              }
            , Cmd.none
            )

        EditZkNote.ShowMessage e ->
            ( displayMessageDialog model e, Cmd.none )

        EditZkNote.Cmd cmd ->
            ( { model | state = EditZkNote emod login }
            , Cmd.map EditZkNoteMsg cmd
            )


handleEditZkNoteListing : Model -> Data.LoginData -> ( EditZkNoteListing.Model, EditZkNoteListing.Command ) -> ( Model, Cmd Msg )
handleEditZkNoteListing model login ( emod, ecmd ) =
    case ecmd of
        EditZkNoteListing.None ->
            ( { model | state = EditZkNoteListing emod login }, Cmd.none )

        EditZkNoteListing.New ->
            ( { model | state = EditZkNote (EditZkNote.initNew login emod.notes emod.spmodel []) login }, Cmd.none )

        EditZkNoteListing.Selected id ->
            ( { model | state = EditZkNoteListing emod login }
            , sendZIMsg model.location (ZI.GetZkNoteEdit { zknote = id })
            )

        EditZkNoteListing.Done ->
            ( { model | state = UserSettings (UserSettings.init login model.fontsize) login (EditZkNoteListing emod login) }
            , Cmd.none
            )

        EditZkNoteListing.Import ->
            ( { model | state = Import (Import.init login emod.notes emod.spmodel) login }
            , Cmd.none
            )

        EditZkNoteListing.Search s ->
            sendSearch { model | state = EditZkNoteListing emod login } s

        EditZkNoteListing.PowerDelete s ->
            ( { model | state = EditZkNoteListing emod login }
            , sendZIMsg model.location
                (ZI.PowerDelete s)
            )

        EditZkNoteListing.SearchHistory ->
            ( shDialog model
            , Cmd.none
            )


handleLogin : Model -> ( Login.Model, Login.Cmd ) -> ( Model, Cmd Msg )
handleLogin model ( lmod, lcmd ) =
    case lcmd of
        Login.None ->
            ( { model | state = Login lmod }, Cmd.none )

        Login.Register ->
            ( { model | state = Login lmod }
            , sendUIMsg model.location
                (UI.Register
                    { uid = lmod.userId
                    , pwd = lmod.password
                    , email = lmod.email
                    }
                )
            )

        Login.Login ->
            ( { model | state = Login lmod }
            , sendUIMsg model.location <|
                UI.Login
                    { uid = lmod.userId
                    , pwd = lmod.password
                    }
            )

        Login.Reset ->
            ( { model | state = Login lmod }
            , sendUIMsg model.location <|
                UI.ResetPassword
                    { uid = lmod.userId
                    }
            )


prevSearchQuery : Data.LoginData -> S.ZkNoteSearch
prevSearchQuery login =
    let
        ts : S.TagSearch
        ts =
            S.Boolex (S.SearchTerm [ S.ExactMatch, S.Tag ] "search")
                S.And
                (S.SearchTerm [ S.User ] login.name)
    in
    { tagSearch = [ ts ]
    , offset = 0
    , limit = Just 50
    , what = "prevSearches"
    , list = False
    }


preinit : Flags -> Url -> Browser.Navigation.Key -> ( PiModel, Cmd Msg )
preinit flags url key =
    ( PreInit
        { flags = flags
        , url = url
        , key = key
        , mbzone = Nothing
        , mbfontsize = Nothing
        }
    , Cmd.batch
        [ Task.perform Zone Time.here
        , LS.getLocalVal { for = "", name = "fontsize" }
        ]
    )


initialPage : Model -> ( Model, Cmd Msg )
initialPage curmodel =
    (case stateLogin curmodel.state of
        Just login ->
            case login.homenote of
                Just id ->
                    ( curmodel
                    , Cmd.batch
                        [ sendZIMsg
                            curmodel.location
                            (ZI.SearchZkNotes <| prevSearchQuery login)
                        , sendZIMsg curmodel.location (ZI.GetZkNoteEdit { zknote = id })
                        ]
                    )

                Nothing ->
                    ( { curmodel
                        | state =
                            EditZkNote
                                (EditZkNote.initNew login
                                    { notes = []
                                    , offset = 0
                                    , what = ""
                                    }
                                    SP.initModel
                                    []
                                )
                                login
                      }
                    , Cmd.batch
                        [ sendZIMsg
                            curmodel.location
                            (ZI.SearchZkNotes <| prevSearchQuery login)
                        ]
                    )

        Nothing ->
            ( { curmodel | state = initLoginState curmodel }, Cmd.none )
    )
        |> (\( m, c ) ->
                ( m
                , Cmd.batch
                    [ Browser.Navigation.replaceUrl m.navkey
                        (routeUrl (stateRoute m.state).route)
                    , c
                    ]
                )
           )


init : Flags -> Url -> Browser.Navigation.Key -> Time.Zone -> Int -> ( Model, Cmd Msg )
init flags url key zone fontsize =
    let
        seed =
            initialSeed (flags.seed + 7)

        adminSettings =
            flags.adminsettings
                |> Maybe.andThen
                    (\v ->
                        JD.decodeValue OD.decodeAdminSettings v
                            |> Result.toMaybe
                    )
                |> Maybe.withDefault { openRegistration = False }

        imodel =
            { state =
                case flags.login of
                    Nothing ->
                        PubShowMessage { message = "loading..." } Nothing

                    Just v ->
                        case
                            JD.decodeValue Data.decodeLoginData v
                        of
                            Ok l ->
                                ShowMessage { message = "loading..." } l Nothing

                            Err e ->
                                PubShowMessage { message = JD.errorToString e } Nothing
            , size = { width = flags.width, height = flags.height }
            , location = flags.location
            , navkey = key
            , seed = seed
            , timezone = zone
            , savedRoute = { route = Top, save = False }
            , prevSearches = []
            , recentNotes = []
            , errorNotes = Dict.empty
            , fontsize = fontsize
            , stylePalette = { defaultSpacing = 10 }
            , adminSettings = adminSettings
            }

        geterrornote =
            flags.errorid
                |> Maybe.map
                    (\id ->
                        PI.getErrorIndexNote flags.location id ErrorIndexNote
                    )
                |> Maybe.withDefault Cmd.none

        setkeys =
            skcommand <|
                WindowKeys.SetWindowKeys
                    [ { key = "s", ctrl = True, alt = False, shift = False, preventDefault = True }
                    , { key = "s", ctrl = True, alt = True, shift = False, preventDefault = True }
                    , { key = "e", ctrl = True, alt = True, shift = False, preventDefault = True }
                    , { key = "r", ctrl = True, alt = True, shift = False, preventDefault = True }
                    , { key = "v", ctrl = True, alt = True, shift = False, preventDefault = True }
                    , { key = "Enter", ctrl = False, alt = False, shift = False, preventDefault = False }
                    , { key = "l", ctrl = True, alt = True, shift = False, preventDefault = True }
                    ]
    in
    parseUrl url
        |> Maybe.andThen
            (\s ->
                case s of
                    Top ->
                        Nothing

                    _ ->
                        Just s
            )
        |> Maybe.map
            (routeState
                imodel
            )
        |> Maybe.map
            (\( rs, rcmd ) ->
                ( { imodel
                    | state = rs
                  }
                , Cmd.batch [ rcmd, geterrornote, setkeys ]
                )
            )
        |> Maybe.withDefault
            (let
                ( m, c ) =
                    initialPage imodel
             in
             ( m
             , Cmd.batch
                [ c
                , geterrornote
                , setkeys
                , Browser.Navigation.replaceUrl key "/"
                ]
             )
            )


main : Platform.Program Flags PiModel Msg
main =
    Browser.application
        { init = preinit
        , view = piview
        , update = piupdate
        , subscriptions =
            \_ ->
                Sub.batch
                    [ receiveTASelection TASelection
                    , Browser.Events.onResize (\w h -> WindowSize { width = w, height = h })
                    , keyreceive
                    , LS.localVal ReceiveLocalVal
                    ]
        , onUrlRequest = urlRequest
        , onUrlChange = UrlChanged
        }


port getTASelection : JE.Value -> Cmd msg


port setTASelection : JE.Value -> Cmd msg


port receiveTASelection : (JD.Value -> msg) -> Sub msg


port receiveKeyMsg : (JD.Value -> msg) -> Sub msg


keyreceive =
    receiveKeyMsg <| WindowKeys.receive WkMsg


port sendKeyCommand : JE.Value -> Cmd msg


skcommand =
    WindowKeys.send sendKeyCommand
