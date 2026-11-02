module Main exposing (main)

import Api
import App exposing (Effect(..), Model, Msg(..))
import Browser
import Http


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> App.init |> run
        , update = \msg model -> App.update msg model |> run
        , view = App.view
        , subscriptions = \_ -> Sub.none
        }


run : ( Model, Effect ) -> ( Model, Cmd Msg )
run ( model, effect ) =
    ( model
    , case effect of
        None ->
            Cmd.none

        LoadCatalog scenario ->
            Http.request
                { method = "GET"
                , headers = []
                , url = "/api/products?scenario=" ++ scenario
                , body = Http.emptyBody
                , expect = Http.expectJson CatalogReceived Api.catalogDecoder
                , timeout = Just 5000
                , tracker = Nothing
                }

        SubmitOrder scenario email cart ->
            Http.request
                { method = "POST"
                , headers = []
                , url = "/api/orders?scenario=" ++ scenario
                , body = Http.jsonBody (Api.orderBody email cart)
                , expect = Http.expectJson OrderReceived Api.receiptDecoder
                , timeout = Just 5000
                , tracker = Nothing
                }
    )
