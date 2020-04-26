-- Sempervivum -- A plant watering tracker
-- Copyright 2020 Ruud van Asseldonk
-- Copyright 2019 Ruud van Asseldonk (in Mindec, github.com/ruuda/mindec)
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- A copy of the License has been included in the root of the repository.

module Html
  ( Html
  , addClass
  , clear
  , div
  , h2
  , img
  , input
  , li
  , node
  , onClick
  , onInput
  , removeClass
  , setId
  , setTitle
  , span
  , text
  , ul
  , withElement
  ) where

import Control.Monad.Reader.Trans (ReaderT (..))
import Dom (Element)
import Dom as Dom
import Effect (Effect)
import Prelude

-- An effect that builds nodes and appends them to the parent.
type Html a = ReaderT Element Effect a

withElement :: Element -> Html Unit -> Effect Unit
withElement container (ReaderT f) = f container

clear :: Html Unit
clear = ReaderT $ \container -> Dom.clearElement container

node :: forall a. String -> Html a -> Html a
node tagName (ReaderT children) =
  ReaderT $ \container -> do
    self <- Dom.createElement tagName
    result <- children self
    Dom.appendChild self container
    pure result

text :: String -> Html Unit
text value = ReaderT $ \container -> Dom.appendText value container

setId :: String -> Html Unit
setId id = ReaderT $ \container -> Dom.setId id container

setTitle :: String -> Html Unit
setTitle title = ReaderT $ \self -> Dom.setAttribute "title" title self

addClass :: String -> Html Unit
addClass className = ReaderT $ \container -> Dom.addClass className container

removeClass :: String -> Html Unit
removeClass className = ReaderT $ \container -> Dom.removeClass className container

onClick :: Effect Unit -> Html Unit
onClick callback = ReaderT $ \container ->
  Dom.addEventListener "click" callback container

onInput :: (String -> Effect Unit) -> Html Unit
onInput callback = ReaderT $ \container ->
  let
    getValueAndCall = do
      value <- Dom.getValue container
      callback value
  in
    Dom.addEventListener "input" getValueAndCall container

div :: forall a. Html a -> Html a
div children = node "div" children

h2 :: forall a. Html a -> Html a
h2 children = node "h2" children

span :: forall a. Html a -> Html a
span children = node "span" children

ul :: forall a. Html a -> Html a
ul children = node "ul" children

li :: forall a. Html a -> Html a
li children = node "li" children

img :: forall a. String -> String -> Html a -> Html a
img src alt (ReaderT children) = ReaderT $ \container -> do
  self <- Dom.createElement "img"
  Dom.setAttribute "src" src self
  Dom.setAttribute "alt" alt self
  result <- children self
  Dom.appendChild self container
  pure result

input :: forall a. String -> Html a -> Html a
input placeholder (ReaderT children) =
  node "input" $ ReaderT $ \self -> do
    Dom.setAttribute "placeholder" placeholder self
    children self
