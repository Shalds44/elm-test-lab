module App exposing (Catalog(..), Checkout(..), Effect(..), Model, Msg(..), init, money, update, view)

import Api exposing (Receipt)
import Cart exposing (Cart, Product)
import Html exposing (Html, a, article, aside, button, code, div, footer, form, h1, h2, h3, header, img, input, label, li, main_, nav, option, p, section, select, small, span, strong, text, ul)
import Html.Attributes exposing (alt, attribute, class, disabled, for, href, id, name, selected, src, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http


type Catalog
    = Loading
    | Loaded (List Product)
    | Failed String


type Checkout
    = Editing
    | Sending
    | Confirmed Receipt
    | Rejected String


type alias Model =
    { catalog : Catalog
    , cart : Cart
    , email : String
    , checkout : Checkout
    , scenario : String
    , events : List String
    }



-- Les effets sont des données inspectables. Main est le seul interpréteur.


type Effect
    = None
    | LoadCatalog String
    | SubmitOrder String String Cart


type Msg
    = CatalogReceived (Result Http.Error (List Product))
    | Add Product
    | Remove String
    | EmailChanged String
    | Submit
    | OrderReceived (Result Http.Error Receipt)
    | ScenarioChanged String
    | Reload


init : ( Model, Effect )
init =
    ( { catalog = Loading, cart = Cart.empty, email = "", checkout = Editing, scenario = "healthy", events = [ "Init → LoadCatalog" ] }
    , LoadCatalog "healthy"
    )


record : String -> Model -> Model
record event model =
    { model | events = List.take 4 (event :: model.events) }


update : Msg -> Model -> ( Model, Effect )
update msg model =
    case ( model.checkout, msg ) of
        ( Sending, OrderReceived result ) ->
            case result of
                Ok receipt ->
                    ( record "OrderReceived → Confirmed" { model | checkout = Confirmed receipt, cart = Cart.empty }, None )

                Err error ->
                    ( record "OrderReceived → Rejected" { model | checkout = Rejected (httpError error) }, None )

        ( Sending, _ ) ->
            -- Bloque les doubles envois et les modifications pendant la requête.
            ( model, None )

        ( _, OrderReceived _ ) ->
            ( model, None )

        ( _, CatalogReceived result ) ->
            case result of
                Ok products ->
                    ( record "CatalogReceived → Loaded" { model | catalog = Loaded products }, None )

                Err error ->
                    ( record "CatalogReceived → Failed" { model | catalog = Failed (httpError error) }, None )

        ( _, Add product ) ->
            ( record "Add → Cart.add" { model | cart = Cart.add product model.cart, checkout = Editing }, None )

        ( _, Remove productId ) ->
            ( record "Remove → Cart.remove" { model | cart = Cart.remove productId model.cart, checkout = Editing }, None )

        ( _, EmailChanged email ) ->
            ( { model | email = email, checkout = Editing }, None )

        ( _, ScenarioChanged scenario ) ->
            ( { model | scenario = scenario }, None )

        ( _, Reload ) ->
            case model.catalog of
                Loading ->
                    ( model, None )

                _ ->
                    ( record "Reload → LoadCatalog" { model | catalog = Loading }, LoadCatalog model.scenario )

        ( _, Submit ) ->
            if List.isEmpty (Cart.lines model.cart) then
                ( { model | checkout = Rejected "Ajoutez au moins un article au panier." }, None )

            else if not (validEmail (String.trim model.email)) then
                ( { model | checkout = Rejected "Saisissez une adresse e-mail valide." }, None )

            else
                case model.catalog of
                    Loading ->
                        ( model, None )

                    _ ->
                        ( record "Submit → Sending" { model | checkout = Sending }
                        , SubmitOrder model.scenario (String.trim model.email) model.cart
                        )


validEmail : String -> Bool
validEmail email =
    let
        noWhitespace =
            not (List.any (\character -> List.member character [ ' ', '\n', '\u{000D}', '\t' ]) (String.toList email))
    in
    case String.split "@" email of
        [ local, domain ] ->
            noWhitespace && not (String.isEmpty local) && List.length (String.split "." domain) >= 2 && List.all (not << String.isEmpty) (String.split "." domain)

        _ ->
            False


httpError : Http.Error -> String
httpError error =
    case error of
        Http.BadStatus status ->
            "Le serveur est indisponible (HTTP " ++ String.fromInt status ++ "). Vous pouvez réessayer."

        Http.BadBody _ ->
            "Réponse JSON invalide : le décodeur Elm a refusé les données."

        Http.NetworkError ->
            "Connexion impossible. Vérifiez le serveur local puis réessayez."

        Http.Timeout ->
            "Le serveur met trop de temps à répondre. Réessayez."

        Http.BadUrl _ ->
            "L’adresse de l’API est invalide."


money : Int -> String
money cents =
    String.fromInt (cents // 100) ++ "," ++ String.padLeft 2 '0' (String.fromInt (modBy 100 cents)) ++ " €"


view : Model -> Html Msg
view model =
    div []
        [ header [ class "topbar" ]
            [ a [ class "brand", href "#" ] [ img [ src "/favicon.svg", alt "", class "brand-mark" ] [], text "elm", span [] [ text " / lab" ] ]
            , nav [ attribute "aria-label" "Navigation principale" ]
                [ a [ href "#pilote", class "active" ] [ text "Le pilote" ]
                , a [ href "#tests" ] [ text "Les tests" ]
                , a [ href "#pourquoi" ] [ text "Pourquoi Elm ?" ]
                ]
            , span [ class "header-note" ] [ span [ class "dot" ] [], text "Projet pédagogique" ]
            ]
        , main_ [ class "page" ]
            [ section [ class "hero" ]
                [ div [ class "hero-copy" ]
                    [ p [ class "eyebrow" ] [ text "ELM · PROJET PILOTE 01" ]
                    , h1 [] [ text "La confiance,", Html.br [] [], span [] [ text "par construction." ] ]
                    , p [ class "intro" ] [ text "Un petit panier. De vraies règles métier. Découvrez comment Elm rend le code prévisible et les tests simples à écrire." ]
                    , div [ class "hero-tags" ] [ span [] [ text "Fonctions pures" ], span [] [ text "Types explicites" ], span [] [ text "Tests génératifs" ] ]
                    ]
                , div [ class "architecture", attribute "aria-label" "Architecture Elm : un événement met à jour le modèle puis la vue" ]
                    [ div [ class "diagram-caption" ] [ span [ class "dot" ] [], text "UNE BOUCLE. UN ÉTAT EXPLICITE." ]
                    , div [ class "diagram-flow" ]
                        [ div [] [ small [] [ text "01" ], strong [] [ text "Message" ], code [] [ text "Add product" ] ]
                        , span [ class "arrow" ] [ text "→" ]
                        , div [] [ small [] [ text "02" ], strong [] [ text "Update" ], code [] [ text "Model → Model" ] ]
                        , span [ class "arrow" ] [ text "→" ]
                        , div [] [ small [] [ text "03" ], strong [] [ text "View" ], code [] [ text "Model → Html" ] ]
                        ]
                    , p [] [ text "Mêmes entrées, même résultat. À chaque fois." ]
                    ]
                ]
            , section [ id "pilote", class "pilot" ]
                [ div [ class "section-heading" ]
                    [ div [] [ p [ class "eyebrow" ] [ text "01 / EXPÉRIMENTER" ], h2 [] [ text "La boutique de l’atelier" ] ]
                    , span [ class "pill" ] [ text "Démo locale · aucun paiement" ]
                    ]
                , div [ class "shop-grid" ]
                    [ div [ class "catalog-side" ] [ catalogView model, networkView model ]
                    , cartView model
                    ]
                , div [ class "state-strip" ]
                    [ div [] [ span [ class "dot" ] [], strong [] [ text "L’état, sans mystère" ], small [] [ text "Les dernières transitions du pilote" ] ]
                    , ul [] (List.map (\event -> li [] [ code [] [ text event ] ]) model.events)
                    ]
                ]
            , learningView
            , section [ id "pourquoi", class "why" ]
                [ div [] [ p [ class "eyebrow" ] [ text "03 / COMPRENDRE" ], h2 [] [ text "Moins de surprises.", Html.br [] [], text "Plus de comportements vérifiés." ] ]
                , div [ class "why-copy" ]
                    [ h3 [] [ text "Le compilateur prépare le terrain." ]
                    , p [] [ text "Un état Loading, Loaded ou Failed oblige à traiter chaque cas. Les décodeurs vérifient les données externes avant qu’elles entrent dans le modèle." ]
                    , h3 [] [ text "Les tests vérifient vos décisions." ]
                    , p [] [ text "Le typage ne sait pas si votre remise doit être de 10 %. Les tests métier le prouvent. Les tests navigateur vérifient ensuite les clics, le HTTP et l’intégration réelle." ]
                    , p [ class "caveat" ] [ text "Elm ne supprime pas tous les bugs : les règles métier, le serveur, les ports JavaScript et l’accessibilité restent à vérifier." ]
                    ]
                ]
            ]
        , footer [] [ span [ class "brand" ] [ text "elm / lab" ], text "Un pilote à lire, à modifier et à tester.", code [] [ text "npm run check" ] ]
        ]


catalogView : Model -> Html Msg
catalogView model =
    case model.catalog of
        Loading ->
            div [ class "catalog-message", attribute "role" "status" ] [ div [ class "loader" ] [], h3 [] [ text "Chargement du catalogue…" ], p [] [ text "Elm attend une réponse HTTP typée." ] ]

        Failed error ->
            div [ class "catalog-message error", attribute "role" "alert" ] [ h3 [] [ text "Le catalogue est indisponible" ], p [] [ text error ], small [] [ text "Choisissez « Réponse normale », puis rechargez le catalogue." ] ]

        Loaded products ->
            div [ class "products" ] (List.map (productView (model.checkout == Sending)) products)


productView : Bool -> Product -> Html Msg
productView busy product =
    article [ class "product" ]
        [ div [ class ("product-art " ++ product.id), attribute "aria-hidden" "true" ]
            [ span [ class "product-number" ]
                [ text
                    (if product.id == "notebook" then
                        "N° 01"

                     else if product.id == "cup" then
                        "N° 02"

                     else
                        "N° 03"
                    )
                ]
            , div [ class "object" ] [ span [] [ text "elm" ] ]
            , span [ class "art-caption" ] [ text "LES ESSENTIELS" ]
            ]
        , div [ class "product-info" ]
            [ small []
                [ text
                    (if product.id == "notebook" then
                        "POUR LES IDÉES"

                     else if product.id == "cup" then
                        "POUR LA PAUSE"

                     else
                        "POUR LE QUOTIDIEN"
                    )
                ]
            , h3 [] [ text product.name ]
            , div [ class "product-bottom" ] [ strong [] [ text (money product.price) ], button [ onClick (Add product), disabled busy, attribute "aria-label" ("Ajouter " ++ product.name) ] [ text "+ Ajouter" ] ]
            ]
        ]


networkView : Model -> Html Msg
networkView model =
    div [ class "network" ]
        [ div [] [ h3 [] [ text "Et si le réseau échouait ?" ], p [] [ text "Choisissez la réponse de la prochaine requête. L’erreur devient un état explicite." ] ]
        , div [ class "network-controls" ]
            [ label [ for "scenario" ] [ text "Scénario réseau" ]
            , select [ id "scenario", onInput ScenarioChanged, disabled (model.checkout == Sending || model.catalog == Loading) ]
                (List.map (\( key, title ) -> option [ value key, selected (model.scenario == key) ] [ text title ]) [ ( "healthy", "Réponse normale" ), ( "unavailable", "Erreur serveur · HTTP 503" ), ( "invalid-json", "JSON invalide · catalogue" ) ])
            , button [ class "secondary", onClick Reload, disabled (model.catalog == Loading || model.checkout == Sending) ] [ text "Recharger le catalogue" ]
            ]
        ]


cartView : Model -> Html Msg
cartView model =
    let
        totals =
            Cart.totals model.cart

        lines =
            Cart.lines model.cart

        busy =
            model.checkout == Sending
    in
    aside [ class "cart", attribute "aria-label" "Votre panier" ]
        [ div [ class "cart-title" ] [ h3 [] [ text "Votre panier" ], span [ class "count" ] [ text (String.fromInt (List.sum (List.map .quantity lines))) ] ]
        , if List.isEmpty lines then
            div [ class "empty-cart" ] [ span [] [ text "+" ], p [] [ text "Tout commence par un article." ], small [] [ text "Ajoutez un essentiel pour tester le panier." ] ]

          else
            ul [ class "cart-lines" ] (List.map (lineView busy) lines)
        , div [ class "offer" ] [ span [] [ text "↗" ], text "Dès 100 € d’articles : −10 % et livraison offerte." ]
        , div [ class "totals" ]
            [ totalRow "Sous-total" (money totals.subtotal)
            , totalRow "Remise (10 %)" ("−" ++ money totals.discount)
            , totalRow "Livraison"
                (if totals.shipping == 0 then
                    "Offerte"

                 else
                    money totals.shipping
                )
            , div [ class "grand-total" ] [ strong [] [ text "Total" ], strong [ attribute "data-testid" "total" ] [ text (money totals.total) ] ]
            ]
        , form [ onSubmit Submit, attribute "novalidate" "" ]
            [ label [ for "email" ] [ text "Adresse e-mail" ]
            , input [ id "email", name "email", type_ "email", value model.email, onInput EmailChanged, disabled busy, Html.Attributes.placeholder "vous@exemple.fr", attribute "autocomplete" "email" ] []
            , button [ class "checkout-button", type_ "submit", disabled (busy || List.isEmpty lines || model.catalog == Loading) ]
                [ text
                    (if busy then
                        "Envoi en cours…"

                     else
                        "Confirmer la commande"
                    )
                , span [] [ text "→" ]
                ]
            ]
        , case model.checkout of
            Confirmed receipt ->
                div [ class "notice success", attribute "role" "status" ] [ strong [] [ text "Commande confirmée" ], p [] [ text (receipt.id ++ " · " ++ money receipt.total) ] ]

            Rejected error ->
                div [ class "notice error", attribute "role" "alert" ] [ text error ]

            _ ->
                text ""
        , small [ class "demo-note" ] [ text "API de démonstration. Aucune commande conservée." ]
        ]


lineView : Bool -> Cart.Line -> Html Msg
lineView busy line =
    li []
        [ div [] [ strong [] [ text line.product.name ], small [] [ text (money (line.product.price * line.quantity)) ] ]
        , div [ class "quantity" ]
            [ button [ onClick (Remove line.product.id), disabled busy, attribute "aria-label" ("Retirer " ++ line.product.name) ] [ text "−" ]
            , span [ attribute "aria-label" ("Quantité " ++ line.product.name) ] [ text (String.fromInt line.quantity) ]
            , button [ onClick (Add line.product), disabled (busy || line.quantity >= 99), attribute "aria-label" ("Augmenter " ++ line.product.name) ] [ text "+" ]
            ]
        ]


totalRow : String -> String -> Html Msg
totalRow title amount =
    div [] [ span [] [ text title ], span [] [ text amount ] ]


learningView : Html Msg
learningView =
    section [ id "tests", class "learning" ]
        [ div [ class "section-heading" ] [ div [] [ p [ class "eyebrow" ] [ text "02 / VÉRIFIER" ], h2 [] [ text "Trois niveaux de confiance" ] ], span [ class "subtle" ] [ text "Du calcul pur au navigateur réel." ] ]
        , div [ class "test-cards" ]
            [ testCard "01" "Les règles métier" "UNITAIRES + FUZZ" "Le total, la remise, les quantités. Des entrées générées pour éprouver les invariants du panier." "npm run test:elm" "CartTest.elm · ApiTest.elm"
            , testCard "02" "Les interactions Elm" "INTÉGRATION EN MÉMOIRE" "Un clic dans la vue produit un message. Le modèle change et la nouvelle vue affiche le résultat." "npm run test:elm" "IntegrationTest.elm"
            , testCard "03" "Le parcours complet" "NAVIGATEUR + HTTP" "Chromium utilise l’application compilée et son API locale : commande, échec serveur et reprise." "npm run test:e2e" "checkout.spec.js"
            ]
        , p [ class "test-note" ] [ text "Ces cartes décrivent les suites du projet. Les résultats réels s’obtiennent dans le terminal ; elles n’exécutent pas les tests." ]
        ]


testCard : String -> String -> String -> String -> String -> String -> Html Msg
testCard number title category description command file =
    article [ class "test-card" ]
        [ div [ class "test-card-top" ] [ span [] [ text number ], small [] [ text category ] ]
        , h3 [] [ text title ]
        , p [] [ text description ]
        , code [] [ text command ]
        , small [ class "test-file" ] [ text file ]
        ]
