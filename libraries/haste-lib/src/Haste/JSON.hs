{-# LANGUAGE CPP                      #-}
{-# LANGUAGE FlexibleInstances        #-}
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings        #-}
{-# LANGUAGE PatternGuards            #-}
-- | Haste-specific JSON library. JSON is common enough that it's a good idea
--   to create as fast and small an implementation as possible. To that end,
--   the parser is implemented entirely in Javascript, and works with any
--   browser that supports JSON.parse; IE does this from version 8 and up, and
--   everyone else has done it since just about forever.
module Haste.JSON (JSON (..), encodeJSON, decodeJSON, toObject, (!), (~>)) where
import Prelude hiding (null)
import Haste
import Haste.Prim
import Data.String as S
#ifndef __HASTE__
#if __GLASGOW_HASKELL__ < 710
import Control.Applicative
#endif
import Haste.Parsing
#else
import System.IO.Unsafe
import Haste.Foreign hiding (toObject)
#endif

-- | Create a Javascript object from a JSON object. Only makes sense in a
--   browser context, obviously.
toObject :: JSON -> JSAny
#ifdef __HASTE__
toObject = jsJSONParse . encodeJSON
jsJSONParse :: JSString -> JSAny
jsJSONParse = unsafePerformIO . go
  where
    go :: JSString -> IO JSAny
    go = ffi "(function(s){return JSON.parse(s);})"
#else
toObject j = error $ "Call to toObject in non-browser: " ++ show j
#endif


-- Remember to update jsParseJSON if this data type changes!
data JSON
  = Num  {-# UNPACK #-} !Double
  | Str  !JSString
  | Bool !Bool
  | Arr  ![JSON]
  | Dict ![(JSString, JSON)]
  | Null

instance IsString JSON where
  fromString = Str . S.fromString

instance JSType JSON where
  toJSString = encodeJSON
  fromJSString x =
    case decodeJSON x of
      Right x' -> Just x'
      _        -> Nothing

numFail :: a
numFail = error "Num JSON: not a numeric JSON node!"

-- | This instance may be a bad idea, but it's nice to be able to create JSOn
--   objects using plain numeric literals.
instance Num JSON where
  (Num a) + (Num b) = Num (a+b)
  _ + _             = numFail
  (Num a) * (Num b) = Num (a*b)
  _ * _             = numFail
  (Num a) - (Num b) = Num (a-b)
  _ - _             = numFail
  negate (Num a)    = Num (negate a)
  negate _          = numFail
  abs (Num a)       = Num (abs a)
  abs _             = numFail
  signum (Num a)    = signum (Num a)
  signum _          = numFail
  fromInteger n     = Num (fromInteger n)

#ifdef __HASTE__
foreign import ccall "jsShow" jsShowD :: Double -> JSString
foreign import ccall "jsStringify" jsStringify :: JSString -> JSString
foreign import ccall "jsParseJSON" jsParseJSON :: JSString -> Ptr (Maybe JSON)
#else
jsShowD :: Double -> JSString
jsShowD = toJSStr . show

jsStringify :: JSString -> JSString
jsStringify = toJSStr . ('"' :) . unq . fromJSStr
  where
    unq ('"' : cs) = "\\\"" ++ unq cs
    unq (c : cs)
      | c == '\\'          = "\\\\" ++ unq cs
      | otherwise          = c : unq cs
    unq _          = ['"']
#endif

-- | Look up a JSON object from a JSON dictionary. Panics if the dictionary
--   isn't a dictionary, or if it doesn't contain the given key.
(!) :: JSON -> JSString -> JSON
dict ! k =
  case dict ~> k of
    Just x -> x
    _      -> error $ "Haste.JSON.!: unable to look up key " ++ fromJSStr k
infixl 5 !

class JSONLookup a where
  -- | Look up a key in a JSON dictionary. Return Nothing if the key can't be
  --   found for some reason.
  (~>) :: a -> JSString -> Maybe JSON
infixl 5 ~>

instance JSONLookup JSON where
  (Dict m) ~> key = lookup key m
  _        ~> _   = Nothing

instance JSONLookup (Maybe JSON) where
  (Just (Dict m)) ~> key = lookup key m
  _               ~> _   = Nothing

encodeJSON :: JSON -> JSString
encodeJSON = catJSStr "" . enc []
  where
    comma   = ","
    openbr  = "["
    closebr = "]"
    opencu  = "{"
    closecu = "}"
    colon   = ":"
    quote   = "\""
    true    = "true"
    false   = "false"
    null    = "null"
    enc acc Null         = null : acc
    enc acc (Str s)      = jsStringify s : acc
    enc acc (Num d)      = jsShowD d : acc
    enc acc (Bool True)  = true : acc
    enc acc (Bool False) = false : acc
    enc acc (Arr elems)
      | (x:xs) <- elems =
        openbr : enc (foldr (\s a -> comma:enc a s) (closebr:acc) xs) x
      | otherwise =
        openbr : closebr : acc
    enc acc (Dict elems)
      | ((key,val):xs) <- elems =
        let encElem (k, v) a = comma : quote : k : quote : colon : enc a v
            encAll = opencu : jsStringify key : colon : encRest
            encRest  = enc (foldr encElem (closecu:acc) xs) val
        in encAll
      | otherwise =
        opencu : closecu : acc

decodeJSON :: JSString -> Either String JSON
#ifdef __HASTE__
decodeJSON = liftMaybe . fromPtr . jsParseJSON
  where
    liftMaybe (Just x) = Right x
    liftMaybe _        = Left "Invalid JSON!"
#else
decodeJSON = liftMaybe . runParser json . fromJSStr
  where
    liftMaybe (Just x) = Right x
    liftMaybe _        = Left "Invalid JSON!"
    json = oneOf [Num  <$> double,
                  Bool <$> boolean,
                  Str  <$> jsstring,
                  Arr  <$> array,
                  Dict <$> object,
                  null]
    jsstring = toJSStr <$> oneOf [quotedString '\'', quotedString '"']
    boolean = oneOf [string "true" >> pure True, string "false" >> pure False]
    null = string "null" >> pure Null
    array = do
      _ <- char '[' >> possibly whitespace
      elements <- commaSeparated json
      _ <- possibly whitespace >> char ']'
      return elements
    commaSeparated p =
      oneOf [do x <- p
                _ <- possibly whitespace >> char ',' >> possibly whitespace
                xs <- commaSeparated p
                return (x:xs),
             do x <- p
                return [x],
             do return []]
    object = do
      _ <- char '{' >> possibly whitespace
      pairs <- commaSeparated kvPair
      _ <- possibly whitespace >> char '}'
      return pairs
    kvPair = do
      k <- jsstring
      _ <- possibly whitespace >> char ':' >> possibly whitespace
      v <- json
      return (k, v)
#endif

instance Show JSON where
  show = fromJSStr . encodeJSON
