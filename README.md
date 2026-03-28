# Baqio

Plugin to allow integration of the data returned by Baqio into Ekylibre.
Based on Baqio API https://api-doc.baqio.com/docs/api-doc/Baqio-Public-API.v1.json

## Installation (from version 1.0)

Add the gem in your ekylibre gemfile :
```
  gem 'ekylibre-baqio', git: 'git@gitlab.com:ekylibre/ekylibre-baqio.git'
```
or in development mode, you can clone the repository in 'ekylibre-baqio' folder near ekylibre and then add in your ekylibre gemfile :
```
  gem 'ekylibre-baqio', path: '../ekylibre-baqio'
```


# ajouter operations dans le point liste des commandes

orders/1560988

"operations"=>
  [{"id"=>12694,
    "account_id"=>140,
    "date"=>"2023-11-02",
    "status"=>"charge",
    "kind"=>"discount_for_early_payment",
    "amount_cents"=>998,
    "amount_currency"=>"EUR",
    "operationable_id"=>1560988,
    "operationable_type"=>"Order",
    "created_at"=>"2023-10-31T08:35:15.294+01:00",
    "updated_at"=>"2023-11-02T09:10:27.394+01:00",
    "register_id"=>nil,
    "accounted_at"=>nil,
    "operation_kind_id"=>1017,
    "customer_id"=>786808,
    "accounting_tax"=>"fr"}]

# ajouter les factures 