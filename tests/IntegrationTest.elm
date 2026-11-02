module IntegrationTest exposing (suite)

import App exposing (Catalog(..), Checkout(..), Effect(..), Msg(..))
import Cart
import Expect
import Html.Attributes as Attr
import Http
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector exposing (attribute, tag, text)


notebook : Cart.Product
notebook =
    { id = "notebook", name = "Carnet de terrain", price = 1800 }


ready : App.Model
ready =
    App.init |> Tuple.first |> App.update (CatalogReceived (Ok [ notebook ])) |> Tuple.first


clickAdd : App.Model -> Result String ( App.Model, Effect )
clickAdd model =
    App.view model
        |> Query.fromHtml
        |> Query.find [ tag "button", attribute (Attr.attribute "aria-label" "Ajouter Carnet de terrain") ]
        |> Event.simulate Event.click
        |> Event.toResult
        |> Result.map (\msg -> App.update msg model)


suite : Test
suite =
    describe "Intégration Elm : vue → événement → update → vue"
        [ test "le clic Ajouter affiche le total avec la livraison" <|
            \_ ->
                case clickAdd ready of
                    Err error ->
                        Expect.fail error

                    Ok ( model, _ ) ->
                        App.view model
                            |> Query.fromHtml
                            |> Query.find [ attribute (Attr.attribute "data-testid" "total") ]
                            |> Query.has [ text "22,90 €" ]
        , test "la soumission de la vue décrit la requête et passe en Sending" <|
            \_ ->
                let
                    withCart =
                        ready |> App.update (Add notebook) |> Tuple.first

                    filled =
                        App.view withCart
                            |> Query.fromHtml
                            |> Query.find [ tag "input", attribute (Attr.id "email") ]
                            |> Event.simulate (Event.input "demo@example.com")
                            |> Event.toResult
                            |> Result.map (\msg -> App.update msg withCart |> Tuple.first)
                in
                case filled of
                    Err error ->
                        Expect.fail error

                    Ok model ->
                        App.view model
                            |> Query.fromHtml
                            |> Query.find [ tag "form" ]
                            |> Event.simulate Event.submit
                            |> Event.toResult
                            |> Result.map (\msg -> App.update msg model)
                            |> Result.map (\( next, effect ) -> ( next.checkout, effect ))
                            |> Expect.equal (Ok ( Sending, SubmitOrder "healthy" "demo@example.com" model.cart ))
        , test "un e-mail invalide n'émet aucune requête" <|
            \_ ->
                let
                    ( model, effect ) =
                        ready |> App.update (Add notebook) |> Tuple.first |> App.update Submit
                in
                Expect.equal ( Rejected "Saisissez une adresse e-mail valide.", None ) ( model.checkout, effect )
        , test "un panier vide ne peut pas être commandé même avec un message direct" <|
            \_ ->
                App.update Submit ready |> Tuple.second |> Expect.equal None
        , test "deux soumissions consécutives ne créent qu'une requête" <|
            \_ ->
                App.update Submit sending |> Expect.equal ( sending, None )
        , test "le panier reste inchangé pendant l'envoi" <|
            \_ ->
                App.update (Remove notebook.id) sending |> Expect.equal ( sending, None )
        , test "une erreur HTTP conserve le panier et autorise une nouvelle tentative" <|
            \_ ->
                let
                    failed =
                        App.update (OrderReceived (Err (Http.BadStatus 503))) sending |> Tuple.first
                in
                Expect.all
                    [ \model -> Expect.equal sending.cart model.cart
                    , \model -> App.update Submit model |> Tuple.first |> .checkout |> Expect.equal Sending
                    , \model -> App.view model |> Query.fromHtml |> Query.find [ attribute (Attr.attribute "role" "alert") ] |> Query.has [ text "HTTP 503" ]
                    ]
                    failed
        , test "la confirmation vide le panier et affiche le montant du serveur" <|
            \_ ->
                let
                    model =
                        sending |> App.update (OrderReceived (Ok { id = "ELM-TEST", total = 2290 })) |> Tuple.first
                in
                Expect.all
                    [ \m -> Expect.equal Cart.empty m.cart
                    , \m -> App.view m |> Query.fromHtml |> Query.find [ attribute (Attr.attribute "role" "status") ] |> Query.has [ text "Commande confirmée", text "ELM-TEST · 22,90 €" ]
                    ]
                    model
        , test "un catalogue illisible est affiché comme une erreur, puis peut être rechargé" <|
            \_ ->
                let
                    failed =
                        ready |> App.update (CatalogReceived (Err (Http.BadBody "incorrect"))) |> Tuple.first
                in
                Expect.all
                    [ \model -> App.view model |> Query.fromHtml |> Query.find [ attribute (Attr.attribute "role" "alert") ] |> Query.has [ text "Réponse JSON invalide" ]
                    , \model -> App.update Reload model |> Tuple.second |> Expect.equal (LoadCatalog "healthy")
                    ]
                    failed
        , test "les événements ne modifient pas l'ancien modèle" <|
            \_ ->
                case clickAdd ready of
                    Err error ->
                        Expect.fail error

                    Ok ( changed, _ ) ->
                        Expect.equal ( 0, 2290 ) ( (Cart.totals ready.cart).total, (Cart.totals changed.cart).total )
        ]


sending : App.Model
sending =
    ready
        |> App.update (Add notebook)
        |> Tuple.first
        |> App.update (EmailChanged "demo@example.com")
        |> Tuple.first
        |> App.update Submit
        |> Tuple.first
