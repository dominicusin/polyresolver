# Детальный план реализации polyresolver по ТЗ

**Версия ТЗ:** 0.2  
**Дата:** 2026-10-19  
**Статус:** В реализации

---

## Архитектура системы

```
┌─────────────────────────────────────────────────────────────────┐
│                        Edge-слой (dnsdist)                      │
│  ACL │ Rate Limiting │ DoT/DoH/DoQ │ Load Balancing             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    polyresolver-core (Haskell)                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │   Routing    │  │  STM Cache   │  │  ResolutionGraph     │   │
│  │   Engine     │  │  (sharded)   │  │  (cycle detection)   │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │  Supervisor  │  │   Engine     │  │  Servant Backend API │   │
│  │  Tree        │  │   (resolve)  │  │  (HTTP/JSON)         │   │
│  └──────────────┘  └──────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Адаптеры (in-process / IPC)                 │
│  Unbound │ ncdns │ EmerDNS │ hsd │ ENS │ Tor │ I2P │ IPFS │ ... │
└─────────────────────────────────────────────────────────────────┘
```

---

## Фаза 0: Базовая инфраструктура (Текущий этап)

### 0.1 DNS Wire Protocol ✅
- [x] Модуль `Polyresolver.DNS.Codec` с кодированием/декодированием заголовка RFC 1035
- [x] Модуль `Polyresolver.DNS.Proxy` для проксирования делегированных зон
- [x] Интеграция прокси в `Polyresolver.DNS.Server`
- [ ] Полная реализация wire-кодирования (questions, answers, authority, additional)

### 0.2 Конфигурация → Адаптеры
- [ ] Загрузка адаптеров из YAML-конфигурации
- [ ] Dependency Injection: `Config -> IO [AdapterEntry]`
- [ ] Регистрация адаптеров в Engine

### 0.3 Делегированные адаптеры
- [x] Проксирование запросов к Unbound (localhost:5335)
- [x] Проксирование запросов к ncdns (localhost:5333)
- [x] Проксирование запросам EmerDNS (localhost:5333)
- [x] Проксирование запросам hsd (localhost:5350)
- [ ] Проверка доступности бэкендов (health-check)

---

## Фаза 1: «Готовые» адаптеры

### 1.1 ncdns — Namecoin → DNS (.bit)
**Приоритет: Высокий**  
**Требования:** ТРЕБ-010, ТРЕБ-006, ТРЕБ-012

#### Задачи:
- [ ] Реализовать `resolveViaNcdns` с полным DNS wire-кодированием
- [ ] Делегированный режим: проксирование на localhost:5333
- [ ] Нативный режим (Фаза 2+): JSON-RPC к namecoind
- [ ] Тесты: запрос A-записи для .bit домена

#### Конфигурация:
```yaml
adapters:
  ncdns:
    mode: delegated
    upstream: "127.0.0.1:5333"
    zones: [".bit"]
    priority: 10
```

### 1.2 EmerDNS — Emercoin NVS
**Приоритет: Высокий**  
**Требования:** ТРЕБ-010, ТРЕБ-006

#### Задачи:
- [ ] Реализовать `resolveViaEmerDNS` с полным DNS wire-кодированием
- [ ] Поддержка зон: .emc, .coin, .lib, .bazar
- [ ] Парсинг NVS-записей в DNS RR

#### Конфигурация:
```yaml
adapters:
  emerdns:
    mode: delegated
    upstream: "127.0.0.1:5333"
    zones: [".emc", ".coin", ".lib", ".bazar"]
    priority: 10
```

### 1.3 hsd/hnsd — Handshake (.hns)
**Приоритет: Высокий**  
**Требования:** ТРЕБ-010, ТРЕБ-006, ТРЕБ-005

#### Задачи:
- [ ] Реализовать `resolveViaHSD` с полным DNS wire-кодированием
- [ ] Поддержка recursive-порта (5349/5350)
- [ ] Проверка версии hsd для определения порта
- [ ] Поддержка native_root_view (опционально)

#### Конфигурация:
```yaml
adapters:
  hsd:
    mode: delegated
    upstream: "127.0.0.1:5350"
    zones: [".hns"]
    priority: 10
    native_root_view: null
```

### 1.4 ENS — Ethereum Name Service (.eth)
**Приоритет: Критически важно**  
**Требования:** ТРЕБ-010, ТРЕБ-006 (КРИТИЧНО: нельзя фабриковать A/AAAA)

#### Задачи:
- [ ] JSON-RPC клиент к Ethereum-ноде
- [ ] ABI-кодирование вызовов Registry/Resolver
- [ ] Реализовать `resolveENSName` через Ethereum RPC
- [ ] Реализовать `resolveContentHash` через Ethereum RPC
- [ ] Поддержка CCIP-Read (EIP-3668)
- [ ] Валидация registry-адреса

#### Конфигурация:
```yaml
adapters:
  ens:
    mode: direct
    ethereum_rpc: "https://localhost:8545"
    registry_address: "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
    zones: [".eth"]
    priority: 10
    fabricate_a_aaaa: false
```

---

## Фаза 2: Расширенные адаптеры и Plugin SDK

### 2.1 Tor — .onion v3 (категория B)
**Приоритет: Средний**

#### Задачи:
- [ ] Валидация формата v3 (56 base32 символов)
- [ ] Возврат `Structured { srKind = CryptoDestination }`
- [ ] Прокси через SOCKS5 (127.0.0.1:9050)

### 2.2 I2P — .i2p (категория B)
**Приоритет: Средний**

#### Задачи:
- [ ] SAM API: `NAMING LOOKUP`
- [ ] Поддержка статических записей

### 2.3 IPFS/IPNS/DNSLink (категория C)
**Приоритет: Средний**

#### Задачи:
- [ ] IPNS: прямой API к IPFS-ноде
- [ ] DNSLink: DNS TXT-запись `_dnslink`
- [ ] Возврат `StructuredKind = ContentHash`

### 2.4 DNSBL — репутационная фильтрация (категория G)
**Приоритет: Средний**

#### Задачи:
- [ ] pre_resolve/post_resolve middleware
- [ ] Поддержка нескольких зон (zen.spamhaus.org и др.)

### 2.5 Plugin SDK — выбор IPC
**Приоритет: Высокий**  
**Требования:** ТРЕБ-012

#### Spike для выбора между Cap'n Proto и gRPC:

| Критерий | Cap'n Proto | gRPC |
|----------|-------------|------|
| Zero-copy | ✅ | ❌ |
| Streaming | ✅ | ✅ |
| Haskell-экосистема | Требует оценки | Доступен |
| Язык-независимость | Ограничена | ✅ |

#### Задачи:
- [ ] Реализовать `Binary` instances для всех типов
- [ ] Добавить сериализацию `PluginRequest`, `PluginResponse`
- [ ] Обработка запросов с capability negotiation
- [ ] Поддержка streaming/async cancel

---

## Фаза 3: Дополнительные сети и OpenTelemetry

### 3.1 GNUnet/GNS (категория D)
- [ ] Делегирование на локальный `gnunet-gns`
- [ ] Поддержка `.alt`/`.gns.alt` pTLD

### 3.2 Reticulum (категория B)
- [ ] listen анонсов RNS
- [ ] petname → destination hash каталог

### 3.3 OLSR (категория E)
- [ ] file-watcher за `/var/run/hosts_olsr`

### 3.4 OpenTelemetry Tracing (MAY)
- [ ] Распространение trace context через ResolutionGraph
- [ ] Span: `resolver.resolve`, `adapter.resolve`, `cache.lookup`

### 3.5 Персистентный кэш
- [ ] SQLite/LMDB backend для warm state между перезапусками
- [ ] Конфигурация: `cache.persistence_path`

---

## Фаза 4: Экспериментальные (enabled: false по умолчанию)

| Адаптер | Статус | Требования |
|---------|--------|------------|
| Yggdrasil | experimental | static_registry |
| cjdns | experimental | delegate_external |
| dn42 | darknet | forward anycast |
| anoNet | darknet | delegate_external |
| Meshtastic | experimental | MQTT directory |
| Babel | experimental | external bridge |
| Serval | experimental | rhizome bridge |
| DRBL | requires уточнения | Distributed Reputation |
| Lantern | transport-only | HTTP proxy |
| Calypso | requires референт | Нужна уточнение |

---

## Требования к тестированию (Раздел 20 ТЗ)

### Уровни тестирования

| Тип | Инструмент | Цель |
|-----|------------|------|
| Unit | hspec/tasty | Чистая логика |
| Property | Hedgehog/QuickCheck | Инварианты кэша, detectCycle |
| Stateful | Hedgehog | Жизненный цикл кэша |
| Concurrency | Déjà Fu | STM deadlock-проверка |
| Golden | — | DNS wire encoding |
| Integration | regtest/testnet | Внешние системы |
| Interoperability | dig/kdig/drill | Wire-совместимость |
| Fuzzing | afl/LL fuzzing | DNS-парсер |
| Load | dnsperf/queryperf | Задержка < 5 мс p50 |

---

## Требования к развертыванию

### Nix Flakes
```nix
{
  description = "polyresolver — universal DNS resolver";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";
  outputs = { self, nixpkgs }: ...
}
```

### Guix
```scheme
(package
  (name "polyresolver")
  (build-system haskell-build-system)
  (inputs (list unbound)))
```

### systemd units
```
/etc/systemd/system/polyresolver.service
/etc/systemd/system/polyresolver-adapters@.service
```

---

## Матрица трассируемости «требование → тест»

| Требование | Тест | Статус |
|------------|------|--------|
| ТРЕБ-001 | TC-ROUTING-001 | ✅ Core |
| ТРЕБ-002 | TC-ROUTING-002 | ✅ Core |
| ТРЕБ-003 | TC-ENGINE-001 | ✅ Core |
| ТРЕБ-006 | TC-ENS-002 | 🟡 Stub |
| ТРЕБ-010 | TC-DNS-001 | 🟡 Partial |
| ТРЕБ-012 | TC-IPC-001 | 🟡 Stub |
| ТРЕБ-013 | TC-API-001 | 🟡 Stub |
| ТРЕБ-014 | TC-CONFIG-001 | 🟡 Stub |
| ТРЕБ-015 | TC-METRICS-001 | 🟡 Stub |
| ТРЕБ-018 | TC-GRAPH-001 | ✅ Core |
| ТРЕБ-020 | TC-SUPER-001 | ✅ Core |

---

## Следующие шаги

1. **Срочно:** Реализовать полное DNS wire-кодирование (questions, answers)
2. **Срочно:** Интегрировать конфигурацию с адаптерами
3. **Среднесрочно:** Реализовать ENS-адаптер через JSON-RPC
4. **Среднесрочно:** Написать property-тесты для кэша и маршрутизации
5. **Долгосрочно:** Реализовать Plugin SDK с выбранным IPC

---

*Документ составлен на основе ТЗ версия 0.2 (17 октября 2026 г.)*