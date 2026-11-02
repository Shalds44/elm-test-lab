module Cart exposing (Cart, Line, Product, add, empty, lines, remove, totals)

import Dict exposing (Dict)


type alias Product =
    { id : String, name : String, price : Int }


type alias Line =
    { product : Product, quantity : Int }



-- Le constructeur reste privé : les quantités passent par les opérations métier.


type Cart
    = Cart (Dict String Line)


empty : Cart
empty =
    Cart Dict.empty


add : Product -> Cart -> Cart
add product (Cart content) =
    Cart
        (Dict.update product.id
            (\existing ->
                case existing of
                    Nothing ->
                        Just { product = product, quantity = 1 }

                    Just line ->
                        Just { line | quantity = min 99 (line.quantity + 1) }
            )
            content
        )


remove : String -> Cart -> Cart
remove id (Cart content) =
    Cart
        (Dict.update id
            (Maybe.andThen
                (\line ->
                    if line.quantity <= 1 then
                        Nothing

                    else
                        Just { line | quantity = line.quantity - 1 }
                )
            )
            content
        )


lines : Cart -> List Line
lines (Cart content) =
    Dict.values content


totals : Cart -> { subtotal : Int, discount : Int, shipping : Int, total : Int }
totals cart =
    let
        subtotal =
            lines cart |> List.map (\line -> line.product.price * line.quantity) |> List.sum

        shipping =
            if subtotal == 0 || subtotal >= 10000 then
                0

            else
                490

        discount =
            if subtotal >= 10000 then
                subtotal // 10

            else
                0
    in
    { subtotal = subtotal, discount = discount, shipping = shipping, total = subtotal - discount + shipping }
