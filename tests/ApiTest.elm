module ApiTest exposing (suite)

import Api
import Cart
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Le contrat JSON"
        [ test "un prix envoyé comme texte est refusé à l'entrée de l'application" <|
            \_ ->
                Decode.decodeString Api.catalogDecoder "[{\"id\":\"notebook\",\"name\":\"Carnet\",\"price\":\"18.00\"}]"
                    |> Expect.err
        , test "un prix négatif est refusé, même si son type JSON est correct" <|
            \_ ->
                Decode.decodeString Api.catalogDecoder "[{\"id\":\"notebook\",\"name\":\"Carnet\",\"price\":-1800}]"
                    |> Expect.err
        , test "un catalogue valide est décodé en produits typés" <|
            \_ ->
                Decode.decodeString Api.catalogDecoder "[{\"id\":\"notebook\",\"name\":\"Carnet\",\"price\":1800}]"
                    |> Expect.equal (Ok [ { id = "notebook", name = "Carnet", price = 1800 } ])
        , test "un champ obligatoire absent est rejeté" <|
            \_ ->
                Decode.decodeString Api.catalogDecoder "[{\"id\":\"notebook\",\"price\":1800}]" |> Expect.err
        , test "une confirmation doit contenir le montant serveur" <|
            \_ ->
                Decode.decodeString Api.receiptDecoder "{\"id\":\"ELM-TEST\"}" |> Expect.err
        , test "la requête n'envoie que les identifiants et quantités, pas les prix client" <|
            \_ ->
                Cart.empty
                    |> Cart.add { id = "notebook", name = "Carnet", price = 1800 }
                    |> Api.orderBody "demo@example.com"
                    |> Encode.encode 0
                    |> Expect.equal "{\"email\":\"demo@example.com\",\"items\":[{\"id\":\"notebook\",\"quantity\":1}]}"
        ]
