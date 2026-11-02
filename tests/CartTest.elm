module CartTest exposing (suite)

import Cart
import Expect
import Fuzz
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "Le panier"
        [ test "un panier vide ne facture ni articles ni livraison" <|
            \_ ->
                Cart.empty |> Cart.totals |> .total |> Expect.equal 0
        , test "deux carnets coûtent 36 euros plus 4,90 euros de livraison" <|
            \_ ->
                Cart.empty
                    |> Cart.add { id = "notebook", name = "Carnet de terrain", price = 1800 }
                    |> Cart.add { id = "notebook", name = "Carnet de terrain", price = 1800 }
                    |> Cart.totals
                    |> .total
                    |> Expect.equal 4090
        , test "à 100 euros, la remise de 10 % et la livraison offerte s'appliquent" <|
            \_ ->
                Cart.empty
                    |> Cart.add { id = "bundle", name = "Ensemble", price = 10000 }
                    |> Cart.totals
                    |> Expect.equal { subtotal = 10000, discount = 1000, shipping = 0, total = 9000 }
        , fuzz (Fuzz.intRange 1 50) "ajouter puis retirer un article conserve le panier initial" <|
            \quantity ->
                let
                    product =
                        { id = "notebook", name = "Carnet", price = 1800 }

                    initial =
                        List.repeat quantity product |> List.foldl Cart.add Cart.empty
                in
                initial |> Cart.add product |> Cart.remove product.id |> Expect.equal initial
        , test "une ligne est limitée à 99 unités, comme le contrat serveur" <|
            \_ ->
                List.repeat 105 { id = "notebook", name = "Carnet", price = 1800 }
                    |> List.foldl Cart.add Cart.empty
                    |> Cart.lines
                    |> List.map .quantity
                    |> Expect.equal [ 99 ]
        , test "à 99,99 euros, aucune remise ni livraison offerte" <|
            \_ ->
                Cart.empty
                    |> Cart.add { id = "threshold", name = "Seuil", price = 9999 }
                    |> Cart.totals
                    |> Expect.equal { subtotal = 9999, discount = 0, shipping = 490, total = 10489 }
        , test "retirer la dernière unité supprime la ligne et la livraison" <|
            \_ ->
                Cart.empty
                    |> Cart.add { id = "one", name = "Article", price = 1800 }
                    |> Cart.remove "one"
                    |> Expect.equal Cart.empty
        , test "retirer un article inconnu ne change pas le panier" <|
            \_ ->
                Cart.empty |> Cart.remove "inconnu" |> Expect.equal Cart.empty
        , test "la remise est arrondie au centime inférieur" <|
            \_ ->
                Cart.empty
                    |> Cart.add { id = "rounding", name = "Arrondi", price = 10009 }
                    |> Cart.totals
                    |> .discount
                    |> Expect.equal 1000
        , fuzz (Fuzz.list (Fuzz.intRange 1 1000000)) "le total reste positif et respecte la décomposition comptable" <|
            \prices ->
                let
                    amounts =
                        prices
                            |> List.indexedMap (\index price -> { id = String.fromInt index, name = "Article", price = price })
                            |> List.foldl Cart.add Cart.empty
                            |> Cart.totals
                in
                Expect.all
                    [ \a -> Expect.atLeast 0 a.total
                    , \a -> Expect.equal (a.subtotal - a.discount + a.shipping) a.total
                    , \a -> Expect.atMost a.subtotal a.discount
                    ]
                    amounts
        , fuzz (Fuzz.list (Fuzz.intRange 1 100000)) "l'ordre d'ajout n'influence pas le total" <|
            \prices ->
                let
                    products =
                        List.indexedMap (\index price -> { id = String.fromInt index, name = "Article", price = price }) prices

                    total items =
                        List.foldl Cart.add Cart.empty items |> Cart.totals
                in
                Expect.equal (total products) (total (List.reverse products))
        ]
