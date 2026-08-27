# ENTERPRISE API ARCHITECTURE LOGIC TH

Repository นี้เป็นแหล่งอ้างอิงหลักสำหรับเอกสาร **AI Native Enterprise Framework (ANEF)** และตรรกะสถาปัตยกรรมระดับ Enterprise ภาษาไทย

## หลักการจัดเก็บทุกเวอร์ชัน

- ทุกเวอร์ชันต้องถูกเก็บแยกไว้ใน `versions/`
- ห้ามเขียนทับหรือลบเวอร์ชันเก่าโดยไม่มีบันทึกการตัดสินใจ
- `current/` ใช้ชี้สถานะของเวอร์ชันที่กำลังพัฒนา
- ทุกเอกสารต้องมี Document ID, Version, Status และ Revision History
- ใช้ Semantic Versioning เช่น `v1.0.0-draft`, `v1.0.0`, `v1.1.0`, `v2.0.0`

## เวอร์ชันปัจจุบัน

- **Version:** `v3.2.0`
- **Status:** Active — Workflow Runtime Foundation
- **Part:** Workflow Runtime Foundation
- **เอกสารล่าสุด:** Workflow Runtime Foundation (`current/workflow-runtime/`)

## โครงสร้าง

```text
.
├── README.md
├── CHANGELOG.md
├── VERSION_INDEX.md
├── current/
│   ├── README.md
│   └── workflow-runtime/
└── versions/
    └── v1.0.0-draft/
        ├── README.md
        └── docs/
            └── 00_FOUNDATION/
```

## เป้าหมาย

ANEF เป็น Framework ที่เป็นกลางต่อภาษา แพลตฟอร์ม ผู้ให้บริการ AI ระบบฐานข้อมูล และ Cloud Provider โดยใช้เอกสาร Contract และหลักฐานทางสถาปัตยกรรมเป็นแหล่งอ้างอิงหลัก

## Runtime และ audit ล่าสุด

- [V3 API Contract Draft](docs/V3_API_CONTRACT_DRAFT.md)
- [API Implementation Matrix](docs/API_IMPLEMENTATION_MATRIX.md)
- [Durable Runtime Gap Analysis](docs/DURABLE_RUNTIME_GAP_ANALYSIS.md)
- [Production Observability Runbook](docs/PRODUCTION_OBSERVABILITY_RUNBOOK.md)
- [Release Artifact / Installer Alignment](docs/RELEASE_ARTIFACT_INSTALLER_ALIGNMENT.md)
- [V1/V2 Compatibility Map](docs/V1_V2_COMPATIBILITY_MAP.md)
- [Delete/Retire Candidates](docs/DELETE_RETIRE_CANDIDATES.md)
- [GUI/UX Audit Status](docs/GUI_UX_AUDIT_STATUS.md)

### ตรวจสอบ local runtime

```text
PYTHONPATH=v3 python -m unittest discover -s v3/tests -p 'test_*.py' -q
PYTHONPATH=tools/research_os_api python -m unittest discover -s tools/research_os_api -p 'test_*.py' -q
```

### Operational scripts

- `v3/scripts/drain_outbox.py` publishes pending queue events in bounded batches.
- `v3/scripts/export_runtime_metrics.py` exports durable event metrics as Prometheus text.

## Tooling / Integration Repository

Repository นี้เป็น **Architecture Source of Truth** และแยกออกจาก Repository สำหรับเครื่องมือเชื่อมต่อและ Implementation

- **Tooling / Integration:** `phakphoum38-stack/flutter`
- Repository เครื่องมือ: https://github.com/phakphoum38-stack/flutter
- Architecture Repository นี้ **ไม่ถูกแทนที่ด้วย tooling repository**
- Tooling สามารถพัฒนา แตก Branch และออก Version ของตัวเองได้ โดยต้องรักษา Compatibility กับ Architecture Contract ที่เกี่ยวข้อง
- การเชื่อมต่อระหว่างสอง Repository ต้องอ้างอิง Contract, Version และ Interface ที่กำหนดอย่างชัดเจน

```text
ENTERPRISE_API_ARCHITECTURE_LOGIC_TH
        │
        │ Architecture Source of Truth
        │ Contract / Version / Interface
        ▼
      flutter
        │
        ├── Integration
        ├── Tooling
        ├── Runtime Support
        └── Implementation
```

หลักการคือ **แยก Architecture ออกจากเครื่องมือ แต่เชื่อมกันด้วย Contract** เพื่อให้สามารถพัฒนาแยกกันได้โดยไม่ทำลายความถูกต้องของ Architecture และ Version เดิม

> Design Once. Build Everywhere. Scale Forever.
