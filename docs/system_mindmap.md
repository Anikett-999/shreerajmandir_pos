# ShreeRajmandir System Architecture (Visual)

This file provides a **designed architecture view** (not just a basic text mindmap), with separate diagrams for layers, runtime flow, and domain/data.

## 1) Layered Architecture

```mermaid
flowchart TB
  %% ===== Styles =====
  classDef ui fill:#fff7f7,stroke:#8C0D20,stroke-width:2px,color:#3c1a1a;
  classDef state fill:#f8fbff,stroke:#285f8f,stroke-width:2px,color:#132b40;
  classDef svc fill:#f8fff9,stroke:#2E7D32,stroke-width:2px,color:#163d18;
  classDef data fill:#fffdf5,stroke:#b8860b,stroke-width:2px,color:#4a3904;
  classDef ext fill:#f5f5f5,stroke:#666,stroke-width:1.5px,color:#222;

  subgraph UI[Presentation Layer - Flutter Screens]
    L[LoginScreen]
    FP[ForgotPasswordScreen]
    AD[AdminDashboard]
    UD[UsersTab]
    CD[CashierDashboard]
    TS[TablesScreen]
  end

  subgraph ST[State Layer]
    AU[AuthService]
    CP[CartProvider]
  end

  subgraph SRV[Application Services]
    SS[StaffSeedService]
    RS[ReportService]
  end

  subgraph DAL[Data Access & Rules]
    FR[firestore.rules]
    UCOL[(users)]
    RCOL[(restaurants)]
    OCOL[(orders / items)]
    KCOL[(kots)]
    MCOL[(menu_items / categories)]
    TCOL[(tables / sections)]
  end

  subgraph EXT[External Firebase]
    FA[(Firebase Auth)]
    FS[(Cloud Firestore)]
    FST[(Firebase Storage)]
  end

  L --> AU
  FP --> AU
  AD --> AU
  UD --> AU
  UD --> SS
  AD --> RS
  CD --> CP
  TS --> CP

  AU --> FA
  AU --> FS
  SS --> FA
  SS --> FS
  RS --> FS

  FR -.guards.-> UCOL
  FR -.guards.-> RCOL
  FR -.guards.-> OCOL
  FR -.guards.-> KCOL
  FR -.guards.-> MCOL
  FR -.guards.-> TCOL

  UCOL --> FS
  RCOL --> FS
  OCOL --> FS
  KCOL --> FS
  MCOL --> FS
  TCOL --> FS
  FST -.optional usage.-> AD

  class L,FP,AD,UD,CD,TS ui;
  class AU,CP state;
  class SS,RS svc;
  class FR,UCOL,RCOL,OCOL,KCOL,MCOL,TCOL data;
  class FA,FS,FST ext;
```

## 2) Auth + Routing Runtime Flow

```mermaid
flowchart TD
  A[App Start] --> B[Firebase Init]
  B --> C[AuthWrapper]
  C --> D{AuthService.isLoading?}
  D -- Yes --> E[Loading Spinner]
  D -- No --> F{isUnlocked?}
  F -- No --> G[LoginScreen]
  F -- Yes --> H{role}
  H -- admin --> I[AdminDashboard]
  H -- cashier --> J[CashierDashboard]
  H -- waiter --> K[TablesScreen]
  H -- unknown --> L[UnauthorizedScreen]

  G --> M[Email/Password Submit]
  M --> N{Validation OK?}
  N -- No --> O[User-friendly error]
  N -- Yes --> P[AuthService.loginWithEmail]
  P --> Q{Firebase/Auth success?}
  Q -- No --> R[Mapped friendly auth errors]
  Q -- Yes --> S[Load user profile from Firestore]
  S --> T[Set role + restaurant + unlock]
  T --> H
```

## 3) Role Capability Map

```mermaid
flowchart LR
  A[admin] --> A1[AdminDashboard]
  A --> A2[UsersTab CRUD]
  A --> A3[Menu / Orders / Revenue / Analytics]

  C[cashier] --> C1[CashierDashboard]
  C --> C2[Billing & collection operations]

  W[waiter] --> W1[TablesScreen]
  W --> W2[Order taking + table flow]
```

## 4) Data Model Snapshot

```mermaid
erDiagram
  USERS {
    string uid PK
    string email
    string name
    string role
    string restaurantId FK
    string phone
    string pin
    string status
    timestamp createdAt
  }

  RESTAURANTS {
    string id PK
    string name
    string adminUid
    timestamp createdAt
  }

  ORDERS {
    string id PK
    string restaurantId FK
    string tableId
    string tableName
    string waiterName
    string status
    number totalAmount
    timestamp createdAt
  }

  KOTS {
    string id PK
    string restaurantId FK
    string orderId FK
    string status
    timestamp createdAt
  }

  USERS }o--|| RESTAURANTS : belongs_to
  ORDERS }o--|| RESTAURANTS : generated_in
  KOTS }o--|| RESTAURANTS : generated_in
  KOTS }o--|| ORDERS : created_from
```

## 5) Operational Notes

- Current active role system in code: `admin`, `cashier`, `waiter`.
- Authentication errors are mapped to user-friendly text.
- Forgot password has validation + cooldown + spam-folder guidance.
- Multi-tenant data scoping uses `restaurantId` and Firestore rules.
