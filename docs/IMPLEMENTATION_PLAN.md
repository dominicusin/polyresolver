# План реализации polyresolver — Техническое задание (ТЗ) версия 0.2

**Дата:** 2026-10-19  
**Статус:** Planning / Implementation plan

---

## Executive Summary

ТЗ описывает универсальный DNS-совместимый резолвер имён для альтернативных, блокчейн- и mesh-сетей. Проект реализует архитектуру с тремя уровнями:
1. **Edge-слой** (dnsdist) — ACL, rate-limiting, терминация DoT/DoH/DoQ
2. **polyresolver-core** — routing, STM-кеш, supervisor tree, ResolutionGraph
3. **Адаптеры** — namespace-specific реализации

---

## Текущее состояние (AUDIT)

| Компонент | Статус | Примечание |
|-----------|--------|------------|
| polyresolver-types | ✅ Реализовано | 13 типов + property-тесты |
| polyresolver-core | ✅ Реализовано | Routing, Cache, Supervisor, Engine |
| polyresolver-dns | 🟡 Частично | Wire-format — заглушка, не использует dnsext |
| polyresolver-api | 🟡 Частично | Servant routes, handlers-заглушки |
| polyresolver-metrics | 🟡 Частично | Stub, нет реальных метрик |
| polyresolver-config | 🟡 Частично | Типы YAML, но без include/env-hot-reload |
| polyresolver-plugin-sdk | 🟡 Частично | ABI/IPC/Client/Server, Binary-методы undefined |
| Adapterы (10 пакетов) | 🟡 Заглушки | Все resolve-функции возвращают NotFound |
| ResolutionGraph | ✅ Реализовано | detectCycle, appendNode, graphDepth |

**Сборка:** `cabal build all` ✅  
**Тесты:** `cabal test all` — 13/13 типов тестов + 5/5 core-тестов ✅

---

## Фаза 0: DNS Wire Protocol и базовая интеграция

### Задачи

#### 0.1 DNS Wire Format через dnsext
**Приоритет: Критически важно**  
**TR Нужно:** ТРЕБ-010 (DNS UDP/TCP 53)

- [ ] `polyresolver-types` — добавить `DNS.Domain`, `DNS.TYPE` из dnsext как типы-Алиасы
- [ ] `polyresolver-dns/src/Polyresolver/DNS/Resolver.hs`:
  - Реализовать `decodeDNSMessage` через `dnsext.Protocol`
  - Реализовать `encodeDNSMessage` через `dnsext.Wire`
  - Добавить `DNSResourceRecord` с правильной десериализацией
- [ ] `polyresolver-dns/src/Polyresolver/DNS/Server.hs`:
  - Исправить дублирование DNSConfig (есть в DNS.hs и Resolver.hs)
  - Подключить Engine к обработке запросов

#### 0.2 Конфигурация → Adapters (Dependency Injection)
**Приоритет: Критически важно**

- [ ] `polyresolver-config/src/Polyresolver/Config/`:
  - Добавить `Resolver (IO AdapterEntry)` в `AdapterConfig`
  - Реализовать `loadAdapters :: Config -> IO [AdapterEntry]`
  - Поддержать hot-reload адаптеров
- [ ] `polyresolver-server/src/Main.hs`:
  - Сгенерировать `Engine` с зарегистрированными адаптерами
  - Интегрировать с reload-механизмом

#### 0.3 Unbound — базовый рекурсивный резолвер
**Приоритет: Высокий** — Фаза 0

- [ ] `polyresolver-adapter-unbound/src/Polyresolver/Adapter/Unbound.hs`:
  - Реализовать `resolveViaUnbound` через DNS wire format
  - Déléguированный режим: пересылка на localhost:5335
  - Health-check: проверка соединения

---

## Фаза 1: «Готовые» адаптеры (5 адаптеров)

### 1.1 ncdns — Namecoin → DNS (.bit)
**TR Нужно:** ТРЕБ-010, ТРЕБ-006, ТРЕБ-012

- [ ] `polyresolver-adapter-ncdns/src/Polyresolver/Adapter/Ncdns.hs`:
  - Режим `delegated`: UDP/TCP на localhost:5333
  - Режим `native` (Фаза 2+): JSON-RPC к namecoind
  - Тесты: запрос через DNS wire format

### 1.2 EmerDNS — Emercoin NVS (.emc, .coin, .lib, .bazar)
**TR Нужно:** ТРЕБ-010, ТРЕБ-006

- [ ] `polyresolver-adapter-emerdns/src/Polyresolver/Adapter/Emerdns.hs`:
  - Подключиться к встроенному DNS-серверу Emercoin
  - Парсинг NVS-записей в DNS RR
  - TTL от ответа бэкенда

### 1.3 hsd/hnsd — Handshake (.hns)
**TR Нужно:** ТРЕБ-010, ТРЕБ-006, ТРЕБ-005

- [ ] `polyresolver-adapter-hsd/src/Polyresolver/Adapter/Hsd.hs`:
  - RPC-запросы к hsd на уровне имени
  - Поддержка native_root_view (опционально)
  - Проверка порта recursive-сервера (5349/5350)

### 1.4 ENS — Ethereum Name Service (.eth)
**TR Нужно:** ТРЕБ-010, ТРЕБ-006 (КРИТИЧНО: нельзя фабриковать A/AAAA)

**Ключевые требования:**
- ENS Registry → Resolver через JSON-RPC
- `addr()` → `StructuredKind = EthAddress`
- `contenthash()` → `StructuredKind = ContentHash` → Delegate в IPFS
- A/AAAA к `.eth` без contenthash → `NotFound`

- [ ] `polyresolver-adapter-ens/src/Polyresolver/Adapter/Ens.hs`:
  - JSON-RPC к Ethereum-ноде (HTTP IPC)
  - ABI кодирование вызовов
  - CCIP-Read поддержка (EIP-3668)
  - Валидация registry-адреса (0x000000...c2e074eC69A0dFb2997BA6C7d2e1e)

---

## Фаза 2: Расширенные адаптеры и Plugin SDK

### 2.1 Tor — .onion v3 (категория B)
**TR Нужно:** ТРЕБ-010

- [ ] `polyresolver-adapter-tor/src/Polyresolver/Adapter/Tor.hs`:
  - Валидация формата v3 (56 base32 символов)
  - Возврат `Structured { srKind = CryptoDestination }`
  - Прокси через SOCKS5 (127.0.0.1:9050)

### 2.2 I2P — .i2p (категория B)
**TR Нужно:** ТРЕБ-010

- [ ] `polyresolver-adapter-i2p/src/Polyresolver/Adapter/I2P.hs`:
  - SAM API: `NAMING LOOKUP`
  - Поддержка статических записей

### 2.3 IPFS/IPNS/DNSLink (категория C)
**TR Нужно:** ТРЕБ-010, ТРЕБ-006

- [ ] `polyresolver-adapter-decentweb/src/Polyresolver/Adapter/Decentweb.hs`:
  - IPNS: прямой API к IPFS-ноде
  - DNSLink: DNS TXT-запись `_dnslink`
  - Возврат `StructuredKind = ContentHash`

### 2.4 DNSBL — репутационная фильтрация (категория G)
**TR Нужно:** middleware-фильтр, не резолвер

- [ ] `polyresolver-adapter-filter/src/Polyresolver/Adapter/Filter.hs`:
  - pre_resolve/post_resolve middleware
  - Поддержка нескольких зон (zen.spamhaus.org и др.)

### 2.5 Plugin SDK — выбор IPC (Phase 2)
**TR Нужно:** ТРЕБ-012

**Spike для выбора между Cap'n Proto и gRPC:**

| Критерий | Cap'n Proto | gRPC |
|----------|-------------|------|
| Zero-copy | ✅ | ❌ |
| Streaming | ✅ | ✅ |
| Haskell-экосистема | Требует оценки | Доступен |
| Язык-независимость | Ограничена | ✅ |

**Рекомендация:** Начать с Cap'n Proto, fallback на gRPC.

- [ ] `polyresolver-plugin-sdk/src/Polyresolver/PluginSDK/IPC.hs`:
  - реализовать `Binary` instances для всех типов
  - Добавить сериализацию `PluginRequest`, `PluginResponse`
- [ ] `polyresolver-plugin-sdk/src/Polyresolver/PluginSDK/Server.hs`:
  - Обработка запросов с capability negotiation
  - Поддержка streaming/async cancel

---

## Фаза 3: Дополнительные сети и OpenTelemetry

### 3.1 GNUnet/GNS (категория D)
- [ ] Делегирование на локальный `gnunet-gns`
- `.alt`/`.gns.alt` pTLD

### 3.2 Reticulum (категория B)
- [ ] listen анонсов RNS
- petname → destination hash каталог

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

### 20.1 Уровни тестирования

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

### 20.2 Матрица трассируемости «требование → тест»

Создать `requirements.yaml`:
```yaml
requirements:
  TREB-001:
    keyword: MUST
    text: "Каждое пространство имён должно иметь ровно один authoritative-адаптер"
    test: TC-ROUTING-001
  TREB-006:
    keyword: MUST_NOT
    text: "Адаптер не должен синтезировать A/AAAA без семантического эквивалента"
    test: TC-ENS-002
```

---

## Требования к развертыванию

### 18.1 Cabal
✅ `cabal.project` настроен, 21 пакет

### 18.2 Nix Flakes
```nix
# flake.nix — требуется создать
{
  description = "polyresolver — universal DNS resolver";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";
  outputs = { self, nixpkgs }: ...
}
```

### 18.3 Guix
```scheme
;; guix.scm — требуется создать
(package
  (name "polyresolver")
  (build-system haskell-build-system)
  (inputs (list unbound)))
```

### 18.4 systemd units
```
# /etc/systemd/system/polyresolver.service
# /etc/systemd/system/polyresolver-adapters@.service (для каждого адаптера)
```

---

## Риски и открытые вопросы (Раздел 23)

| # | Вопрос | Статус | Действие |
|---|--------|--------|----------|
| 1 | Refерент "Calypso" | `[Не проверено]` | Уточнить у разработчика |
| 5 | IPC: Cap'n Proto vs gRPC | Открыт | Spike в начале Фазы 2 |
| 6 | Протоколы Meshtastic/Babel/Serval | `[Не проверено]` | Отложить до Фазы 4 |

---

## План миграции конфигурации

Текущая конфигурация в ТЗ (YAML) должна маппиться на внутренние типы:

```yaml
listeners:
  dns:
    - transport: udp, address: "127.0.0.1", port: 5300
    - transport: tcp, address: "127.0.0.1", port: 5300
routing:
  conflict_policy: explicit
  conflicts:
    - suffix: ".bit", winner: "ncdns"
```

---

## Следующие шаги

1. **Срочно**: Синхронизировать `Types.hs` и `Types/Zone.hs` — дубликат `ZonePattern` с разной семантикой Eq
2. **Срочно**: Исправить дублирование DNSConfig между DNS.hs и Resolver.hs
3. **Срочно**: Реализовать DNS wire encoding через dnsext
4. **Среднесрочно**: Написать property-тест `detectCycle` (уже есть в types-tests, нужно добавить в core)
5. **Среднесрочно**: Интегрировать конфигурацию с адаптерами
6. **Долгосрочно**: Реализовать Plugin SDK с выбранным IPC

---

## Приложение: Карта требований к файлам

| Требование | Файл | Статус |
|------------|------|--------|
| ТРЕБ-001 | Routing, Adapter | ✅ Core реализует |
| ТРЕБ-002 | Routing | ✅ Explicit ConflictPolicy |
| ТРЕБ-003 | Engine | ✅ NoRoute → NotFound |
| ТРЕБ-006 | Types.Result | ✅ ResolveResult = Classic\|Structured\|Delegate\|NotFound |
| ТРЕБ-010 | polyresolver-dns | 🟡 Stub |
| ТРЕБ-012 | Plugin SDK | 🟡 Stub (Binary undefined) |
| ТРЕБ-013 | polyresolver-api | 🟡 Stub handlers |
| ТРЕБ-014 | polyresolver-config | 🟡 без include/hot-reload |
| ТРЕБ-015 | polyresolver-metrics | 🟡 Stub |
| ТРЕБ-018 | Types.Graph | ✅ detectCycle реализован |
| ТРЕБ-020 | Supervisor | ✅ изоляция через supervisor tree |

---

*Документ составлен на основе ТЗ версия 0.2 (17 октября 2026 г.)*