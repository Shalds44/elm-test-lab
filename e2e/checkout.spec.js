import { test, expect } from '@playwright/test';

test('commande complète : Elm → HTTP → API locale → confirmation', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Ajouter Sac quotidien' }).click({ clickCount: 3 });
  await expect(page.getByTestId('total')).toHaveText('113,40 €');
  await page.getByLabel('Adresse e-mail').fill('demo@example.com');
  const responsePromise = page.waitForResponse(r => r.url().includes('/api/orders') && r.request().method() === 'POST');
  await page.getByRole('button', { name: 'Confirmer la commande' }).click();
  const response = await responsePromise;
  expect(response.status()).toBe(201);
  expect(response.request().postDataJSON()).toEqual({ email: 'demo@example.com', items: [{ id: 'bag', quantity: 3 }] });
  expect(await response.json()).toMatchObject({ total: 11340 });
  await expect(page.getByRole('status')).toContainText('Commande confirmée');
  await expect(page.getByTestId('total')).toHaveText('0,00 €');
});

test('une erreur de commande conserve le panier, puis une nouvelle tentative aboutit', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Ajouter Carnet de terrain' }).click();
  await page.getByLabel('Adresse e-mail').fill('demo@example.com');
  await page.getByLabel('Scénario réseau').selectOption('unavailable');
  await page.getByRole('button', { name: 'Confirmer la commande' }).click();
  await expect(page.getByRole('alert')).toContainText('HTTP 503');
  await expect(page.getByTestId('total')).toHaveText('22,90 €');
  await page.getByLabel('Scénario réseau').selectOption('healthy');
  await page.getByRole('button', { name: 'Confirmer la commande' }).click();
  await expect(page.getByRole('status')).toContainText('Commande confirmée');
});

test('un JSON incompatible est refusé et le catalogue peut être rechargé', async ({ page }) => {
  await page.goto('/');
  await page.getByLabel('Scénario réseau').selectOption('invalid-json');
  await page.getByRole('button', { name: 'Recharger le catalogue' }).click();
  await expect(page.getByRole('alert')).toContainText('Réponse JSON invalide');
  await expect(page.getByRole('button', { name: /Ajouter/ })).toHaveCount(0);
  await page.getByLabel('Scénario réseau').selectOption('healthy');
  await page.getByRole('button', { name: 'Recharger le catalogue' }).click();
  await expect(page.getByRole('button', { name: /Ajouter/ })).toHaveCount(3);
});

test('une panne du catalogue est un état visible et récupérable', async ({ page }) => {
  await page.goto('/');
  await page.getByLabel('Scénario réseau').selectOption('unavailable');
  await page.getByRole('button', { name: 'Recharger le catalogue' }).click();
  await expect(page.getByRole('alert')).toContainText('HTTP 503');
  await page.getByLabel('Scénario réseau').selectOption('healthy');
  await page.getByRole('button', { name: 'Recharger le catalogue' }).click();
  await expect(page.getByRole('button', { name: /Ajouter/ })).toHaveCount(3);
});

test('un e-mail invalide ne déclenche aucune requête de commande', async ({ page }) => {
  const orders = [];
  page.on('request', r => { if (r.url().includes('/api/orders')) orders.push(r); });
  await page.goto('/');
  await page.getByRole('button', { name: 'Ajouter Tasse atelier' }).click();
  await page.getByLabel('Adresse e-mail').fill('adresse-invalide');
  await page.getByRole('button', { name: 'Confirmer la commande' }).click();
  await expect(page.getByRole('alert')).toContainText('adresse e-mail valide');
  expect(orders).toHaveLength(0);
});

test('le retrait de la dernière unité annule la livraison', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Ajouter Tasse atelier' }).click();
  await expect(page.getByTestId('total')).toHaveText('28,90 €');
  await page.getByRole('button', { name: 'Retirer Tasse atelier' }).click();
  await expect(page.getByTestId('total')).toHaveText('0,00 €');
  await expect(page.getByRole('button', { name: 'Confirmer la commande' })).toBeDisabled();
});

test('le serveur refuse un article inconnu et une quantité invalide', async ({ request }) => {
  for (const item of [{ id: 'unknown', quantity: 1 }, { id: 'bag', quantity: 0 }, { id: 'bag', quantity: 100 }]) {
    const response = await request.post('/api/orders', { data: { email: 'demo@example.com', items: [item] } });
    expect(response.status()).toBe(400);
  }
});

test('le serveur recalcule le montant malgré un prix falsifié par le client', async ({ request }) => {
  const response = await request.post('/api/orders', {
    data: { email: 'demo@example.com', total: 1, items: [{ id: 'bag', quantity: 3, price: 1 }] },
  });
  expect(response.status()).toBe(201);
  expect(await response.json()).toMatchObject({ total: 11340 });
});

test('sur mobile, le panier fonctionne sans débordement horizontal', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByRole('button', { name: 'Ajouter Carnet de terrain' }).click();
  await expect(page.getByTestId('total')).toHaveText('22,90 €');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('mobile.png'), fullPage: true });
});

test('la page de démonstration ne produit aucune erreur JavaScript', async ({ page }, testInfo) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('/');
  await expect(page.getByRole('button', { name: /Ajouter/ })).toHaveCount(3);
  await page.screenshot({ path: testInfo.outputPath('desktop.png'), fullPage: true });
  expect(errors).toEqual([]);
});
