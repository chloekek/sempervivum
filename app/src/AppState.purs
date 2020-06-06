-- Sempervivum -- A plant watering tracker
-- Copyright 2020 Ruud van Asseldonk
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- A copy of the License has been included in the root of the repository.

module AppState
  ( AppState
  , downloadAsJson
  , getMatchedPlants
  , getPlants
  , insertPlant
  , open
  , postWatered
  , postWateredFertilized
  ) where

import Prelude

import Control.Monad.Error.Class (class MonadThrow, throwError)
import Control.Monad.Reader.Class (ask)
import Data.Argonaut.Decode (decodeJson) as Json
import Data.Argonaut.Encode (encodeJson) as Json
import Data.Either (Either (..))
import Data.Time.Duration (Milliseconds (..))
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Aff as Aff
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Exception (Error, error)

import Care (MatchedPlants)
import Idb (Db)
import Plant (Plants, Plant)
import Species (Catalog)
import Time (Instant)
import Var (Var)

import Blob as Blob
import Care as Care
import Dom as Dom
import Html as Html
import Idb as Idb
import Plant as Plant
import Var as Var

type AppState =
  { db :: Db
  , catalog :: Catalog
  , plants :: Var Plants
  }

fatal :: forall m a. MonadThrow Error m => String -> m a
fatal = error >>> throwError

open :: Catalog -> Aff AppState
open catalog = do
  db         <- Idb.open
  plantsJson <- Idb.getJson "plants" db
  plants     <- case Json.decodeJson plantsJson of
    Right ps -> pure ps
    Left err -> fatal $ "Failed to parse plants: " <> err

  var <- liftEffect $ Var.create plants

  pure { db: db, catalog: catalog, plants: var }

-- Add (or replace if the plant with that id already exists) a plant to the app
-- state.
insertPlant :: AppState -> Plant -> Aff Unit
insertPlant appState plant = do
  -- Update the deserialized plant list in the mutable volatile app state.
  -- We don't reload the plant list from IndexedDB, so if you open two tabs,
  -- you may lose data. I consider that acceptable, it is easier than
  -- integrating IndexedDB operations deeply with PureScript types.
  plants <- liftEffect $ Var.get appState.plants
  let newPlants = Plant.insertPlant plant plants
  liftEffect $ Var.set appState.plants newPlants
  -- Also persist the new plant list in IndexedDB.
  Idb.putJson "plants" (Json.encodeJson newPlants) appState.db

-- Record a watered event for the given plant at the given time, then replace
-- the plant in the app state, return the new plant.
postWatered :: AppState -> Instant -> Plant -> Aff Plant
postWatered appState now plant =
  let
    newPlant = Plant.recordWatered now plant
  in do
    insertPlant appState newPlant
    pure newPlant

-- Record a watered and fertilized event for the given plant at the given time,
-- then replace the plant in the app state, return the new plant.
postWateredFertilized :: AppState -> Instant -> Plant -> Aff Plant
postWateredFertilized appState now plant =
  let
    newPlant = Plant.recordFertilized now $ Plant.recordWatered now $ plant
  in do
    insertPlant appState newPlant
    pure newPlant

getPlants :: AppState -> Effect Plants
getPlants appState = Var.get appState.plants

getMatchedPlants :: AppState -> Effect MatchedPlants
getMatchedPlants appState = do
  plants <- Var.get appState.plants
  pure $ Care.match appState.catalog plants

-- Trigger a download of the plant list as json.
downloadAsJson :: AppState -> Effect Unit
downloadAsJson appState = do
  plants <- Var.get appState.plants
  url <- Blob.getObjectUrl $ Blob.toBlob $ Json.encodeJson plants
  Console.log $ "Can download at " <> url

  -- Kind of hack, but it seems like this is the proper way to do it:
  -- We create an <a> element with href set to the object url, and "download"
  -- attribute set. We never attach it to the document, we only .click() it to
  -- trigger the download. We put it in a div because it is easier with the Html
  -- monad.
  outer <- Dom.createElement "div"
  a <- Html.withElement outer $ do
    Html.a url $ do
      -- After click, "revoke" the url we just generated, to release the
      -- resources. We can't do this immediately in onClick, because it runs
      -- before the download starts, so delay it with Aff.
      Html.onClick $ Aff.launchAff_ $ do
        Aff.delay (Milliseconds 1.0)
        liftEffect $ Blob.revokeObjectUrl url

      -- TODO: Set download attribute.
      ask

  Dom.clickElement a
