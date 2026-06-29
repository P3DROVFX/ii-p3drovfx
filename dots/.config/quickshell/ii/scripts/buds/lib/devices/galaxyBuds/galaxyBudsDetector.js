import {
    GalaxyBudsModel, BudsUUID, BudsLegacyUUID, DeviceIdPrefixUUID
} from './galaxyBudsConfig.js';

export function checkForSamsungBuds(uuids, name) {
    if (uuids.includes(BudsLegacyUUID))
        return GalaxyBudsModel.GalaxyBuds;

    if (!uuids.includes(BudsUUID))
        return null;

    let model = null;

    const coloredGuid = uuids.find(g => g.startsWith(DeviceIdPrefixUUID));
    if (coloredGuid) {
        const hexId = coloredGuid.slice(DeviceIdPrefixUUID.length);
        if (hexId.length === 4) {
            const id = parseInt(hexId, 16);

            switch (id) {
                case 0x0101:
                    model = GalaxyBudsModel.GalaxyBuds;
                    break;

                case 0x0102: case 0x0103: case 0x0104: case 0x0105:
                case 0x0106: case 0x0107: case 0x0108: case 0x0109:
                case 0x010A:
                    model = GalaxyBudsModel.GalaxyBudsPlus;
                    break;

                case 0x0116: case 0x0117: case 0x0118:
                case 0x0119: case 0x011A: case 0x011B: case 0x011C:
                    model = GalaxyBudsModel.GalaxyBudsLive;
                    break;

                case 0x012A: case 0x012B:
                case 0x012C: case 0x012D:
                    model = GalaxyBudsModel.GalaxyBudsPro;
                    break;

                case 0x0139: case 0x013A: case 0x013B: case 0x013C:
                case 0x013D: case 0x013E: case 0x013F: case 0x0140:
                case 0x0141: case 0x3801:
                    model = GalaxyBudsModel.GalaxyBuds2;
                    break;

                case 0x0142: case 0x0143:
                    model = GalaxyBudsModel.GalaxyBudsCore;
                    break;

                case 0x0145: case 0x0146: case 0x0147: case 0x0148:
                    model = GalaxyBudsModel.GalaxyBuds2Pro;
                    break;

                case 0x014A: case 0x014B:
                    model = GalaxyBudsModel.GalaxyBudsFe;
                    break;

                case 0x014D: case 0x014E:
                    model = GalaxyBudsModel.GalaxyBuds3;
                    break;

                case 0x0154: case 0x0155:
                    model = GalaxyBudsModel.GalaxyBuds3Pro;
                    break;

                case 0x015B: case 0x015C:
                    model = GalaxyBudsModel.GalaxyBuds3Fe;
                    break;

                case 0x0163: case 0x0164:
                    model = GalaxyBudsModel.GalaxyBuds4;
                    break;

                case 0x0167: case 0x0168: case 0x0169:
                    model = GalaxyBudsModel.GalaxyBuds4Pro;
                    break;
            }
        }
    }

    if (!model && name) {
        const lower = name.toLowerCase();
        const normalized = lower.replace(/[\s\-_]+/g, '');

        if (normalized.includes('buds4pro'))
            model = GalaxyBudsModel.GalaxyBuds4Pro;
        else if (normalized.includes('buds3pro'))
            model = GalaxyBudsModel.GalaxyBuds3Pro;
        else if (normalized.includes('buds2pro'))
            model = GalaxyBudsModel.GalaxyBuds2Pro;
        else if (normalized.includes('budspro'))
            model = GalaxyBudsModel.GalaxyBudsPro;

        else if (normalized.includes('buds3fe'))
            model = GalaxyBudsModel.GalaxyBuds3Fe;
        else if (normalized.includes('budsfe'))
            model = GalaxyBudsModel.GalaxyBudsFe;

        else if (normalized.includes('buds4'))
            model = GalaxyBudsModel.GalaxyBuds4;
        else if (normalized.includes('buds3'))
            model = GalaxyBudsModel.GalaxyBuds3;
        else if (normalized.includes('buds2'))
            model = GalaxyBudsModel.GalaxyBuds2;

        else if (normalized.includes('budslive'))
            model = GalaxyBudsModel.GalaxyBudsLive;
        else if (normalized.includes('buds+') || normalized.includes('budsplus'))
            model = GalaxyBudsModel.GalaxyBudsPlus;
        else if (normalized.includes('budscore'))
            model = GalaxyBudsModel.GalaxyBudsCore;
    }

    if (!model)
        return null;

    return model;
}

