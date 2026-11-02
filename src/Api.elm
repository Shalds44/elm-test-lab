module Api exposing (Receipt, catalogDecoder, orderBody, receiptDecoder)

import Cart exposing (Product)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


catalogDecoder : Decoder (List Product)
catalogDecoder =
    Decode.list
        (Decode.map3 Product
            (Decode.field "id" Decode.string)
            (Decode.field "name" Decode.string)
            (Decode.field "price" nonNegativeMoney)
        )


nonNegativeMoney : Decoder Int
nonNegativeMoney =
    Decode.int
        |> Decode.andThen
            (\amount ->
                if amount >= 0 && amount <= 1000000 then
                    Decode.succeed amount

                else
                    Decode.fail "Le montant doit être compris entre 0 et 1 000 000 centimes."
            )


type alias Receipt =
    { id : String, total : Int }


receiptDecoder : Decoder Receipt
receiptDecoder =
    Decode.map2 Receipt
        (Decode.field "id" Decode.string)
        (Decode.field "total" Decode.int)


orderBody : String -> Cart.Cart -> Encode.Value
orderBody email cart =
    Encode.object
        [ ( "email", Encode.string email )
        , ( "items"
          , Encode.list
                (\line -> Encode.object [ ( "id", Encode.string line.product.id ), ( "quantity", Encode.int line.quantity ) ])
                (Cart.lines cart)
          )
        ]
