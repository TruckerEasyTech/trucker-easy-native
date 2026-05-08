//
//  Localizable.xcstrings
//  Trucker Easy - Multi-language Support
//
//  Base: English (en)
//  Additional: Spanish (es), Portuguese (pt-BR)
//

/*
Xcode String Catalog Format (.xcstrings)

To implement: 
1. Create Localizable.xcstrings in Xcode
2. Add source language: English
3. Add localizations: Spanish, Portuguese (Brazil)

Key Translations:

{
  "sourceLanguage" : "en",
  "strings" : {
    "My Horizon" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "My Horizon" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Mi Horizonte" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Meu Horizonte" } }
      }
    },
    "Got Load?" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Got Load?" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "¿Tienes Carga?" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Recebeu Carga?" } }
      }
    },
    "My Check-up" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "My Check-up" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Mi Chequeo" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Meu Check-up" } }
      }
    },
    "How are you feeling today?" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "How are you feeling today?" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "¿Cómo te sientes hoy?" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Como você está se sentindo hoje?" } }
      }
    },
    "My Cabin" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "My Cabin" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Mi Cabina" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Minha Cabine" } }
      }
    },
    "Road Talk" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Road Talk" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Charla de Carretera" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Papo de Estrada" } }
      }
    },
    "Chat with Easy" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Chat with Easy" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Habla con Easy" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Conversar com Easy" } }
      }
    },
    "Driver to Driver" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Driver to Driver" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "De Conductor a Conductor" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "De Motorista para Motorista" } }
      }
    },
    "Created by a driver, for drivers." : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Created by a driver, for drivers." } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Creado por un conductor, para conductores." } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Criado por um motorista, para motoristas." } }
      }
    },
    "Start Free Trial" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Start Free Trial" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Iniciar Prueba Gratis" } },
        "pt-BR" : { "stringUnit" : { "state" : "translated", "value" : "Iniciar Teste Grátis" } }
      }
    }
  },
  "version" : "1.0"
}

Usage in SwiftUI:
Text("My Horizon") // Automatically localized
Text("Got Load?")   // Automatically localized
*/

import Foundation

// Localization Helper
struct LocalizedString {
    static func get(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
